{
  description = "Write by Stylus Labs - cross-platform handwritten notes app (Linux + Android builds, AGPL-3.0)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      pre-commit-hooks,
    }:
    flake-utils.lib.eachSystem
      [
        "x86_64-linux"
        "aarch64-linux"
      ]
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = {
              # The Android SDK packages are marked "unfree" in nixpkgs.
              allowUnfree = true;
              # We agree to the Android SDK license on the user's behalf.
              android_sdk.accept_license = true;
            };
          };
          inherit (pkgs) lib;

          /*
            ------------------------------------------------------------------
            Git submodules
            ------------------------------------------------------------------
            The upstream repo keeps its dependencies as gitlinks. They are
            *uninitialized* in a fresh clone, and the Nix store can only ever
            contain fully materialized trees — so the flake pins the exact
            upstream revisions (taken from `git ls-tree HEAD <path>`) and
            fetches them as immutable, content-addressed store paths at
            evaluation time (network required on first use, cached afterwards).

            These are then spliced into a fresh source tree used by *every*
            package/dev-shell build — this is the Nix-flake equivalent of
            `git submodule update --init --recursive`, and it is verified from
            a clean checkout (the flake source has no .git, so plain
            `builtins.fetchGit self` cannot provide submodules).

            NOTE: the Linux build uses USE_SYSTEM_SDL=1, so the SDL submodule
            contents are only needed for Android/Windows builds; it is still
            spliced in for consistency. The SDL gitlink (bf28970) is only
            reachable from the `write-win` ref of that fork, hence the `ref`.
            ------------------------------------------------------------------
          */
          submodules = {
            SDL = {
              url = "https://github.com/pbsurf/SDL";
              rev = "bf28970b2db9844277794174b2fa87e25c9a9862";
              # That commit is only reachable from the `write-win` ref of the
              # fork, so fetchGit must be told which ref to look at.
              ref = "refs/heads/write-win";
            };
            nanovgXC = {
              url = "https://github.com/styluslabs/nanovgXC";
              rev = "dce4a2cc5ddece35bafd5a0cd7d917113981837e";
            };
            ugui = {
              url = "https://github.com/styluslabs/ugui";
              rev = "7a8c0f5e341bba752486d3d04be193e89519f2c8";
            };
            ulib = {
              url = "https://github.com/styluslabs/ulib";
              rev = "e3d789ed09d1e04a06bf415af35c802715c70aa0";
            };
            usvg = {
              url = "https://github.com/styluslabs/usvg";
              rev = "d086784ad5b8879f8000e22d7916e425917f75ac";
            };
            pugixml = {
              url = "https://github.com/zeux/pugixml";
              rev = "101f32884f794130d16b8c663883528caefd5b7f";
            };
            miniz = {
              url = "https://github.com/richgel999/miniz";
              rev = "336fca3bd497d0c10e156b9ed08468d32bfeef94";
            };
            stb = {
              url = "https://github.com/nothings/stb";
              rev = "f75e8d1cad7d90d72ef7a4661f1b994ef78b4e31";
            };
          };

          fetchSubmodule = args: builtins.fetchGit (args // { shallow = true; });
          fetchedSubmodules = lib.mapAttrs (_: fetchSubmodule) submodules;
          # Android's SDL build files do not exist at the superproject's Windows
          # SDL gitlink. This is a separate, immutable Android build dependency,
          # not an implicit `git switch`: scripts/check android and write-android
          # both consume this exact commit.
          androidSdl = builtins.fetchGit {
            url = "https://github.com/pbsurf/SDL";
            rev = "0794cabc4e12cb0bdde2c8ff7f390f999a671c4a";
            ref = "refs/heads/write-android";
            shallow = true;
          };

          # A single writable, fully-initialized source tree:
          #   * the flake source (the Write app) at the root
          #   * every submodule spliced into place
          #   * Makefile/Android.mk patches that hard-code the maintainer's
          #     home directory or demand a specific git branch in the sandbox
          writeSource = pkgs.runCommand "write-source" { } (
            ''
              cp -r ${self} $out
              chmod -R u+w $out
              find "$out" -name .git -type d -prune -exec rm -rf {} + 2>/dev/null || true
            ''
            + lib.concatMapStringsSep "\n" (name: ''
              rm -rf "$out/${name}"
              cp -r "${fetchedSubmodules.${name}}" "$out/${name}"
              chmod -R u+w "$out/${name}"
            '') (builtins.attrNames submodules)
            + ''
              # (GITREV / GITCOUNT in the Makefile evaluate to empty strings in
                #  the store because there is no .git — harmless, they are only
                #  used for build/package naming.)
            ''
          );

          # Android source is identical except for its explicitly pinned SDL
          # checkout. Keeping this separate preserves the superproject gitlink
          # for normal development and avoids mutable branch switching.
          androidWriteSource = pkgs.runCommand "write-android-source" { } ''
            cp -r ${writeSource} $out
            chmod -R u+w $out
            rm -rf "$out/SDL"
            cp -r ${androidSdl} "$out/SDL"
            chmod -R u+w "$out/SDL"
          '';

          # Regenerate the embedded string/icon resources with embed.py so the
          # binaries always match the checked-in icons/*.svg & strings/*.xml.
          # (embed.py --compress needs gzip + xxd on PATH.)
          generateResources = ''
            ( cd scribbleres
              python3 embed.py icons/*.svg > res_icons.cpp
              python3 embed.py --compress strings/*.xml > res_strings.cpp
            )
          '';

          /*
            ------------------------------------------------------------------
            Android SDK / NDK
            ------------------------------------------------------------------
            Unfree intermediate steps are resolved lazily, so `nix build
            .#write-linux` never evaluates these (~GB download only hit when
            the Android tooling is actually used).

            Versions verified against this checkout:
            - build.gradle pins ndkVersion '26.3.11579264' (see
              syncscribble/android/app/build.gradle)
            - compileSdk 30 / AGP 8.x needs build-tools 34.0.0 (+30.0.3 legacy)
            - gww wrapper uses the SDK's cmake 3.18.1 for the JNI build
            ------------------------------------------------------------------
          */
          androidComposition = pkgs.androidenv.composeAndroidPackages {
            cmdLineToolsVersion = "16.0"; # provides sdkmanager/aapt
            platformToolsVersion = "37.0.1"; # adb
            buildToolsVersions = [
              "34.0.0"
              "30.0.3"
            ]; # AGP 8.4 default + legacy
            platformVersions = [
              "30"
              "34"
            ]; # compileSdk 30 + 34 for AGP
            includeNDK = true;
            ndkVersion = "26.3.11579264"; # the version build.gradle pins
            cmakeVersions = [ "3.18.1" ];
            includeEmulator = false;
            includeSources = false;
            useGoogleAPIs = false;
          };
          # NOTE: attribute selection on the compose *call* directly
          # (`...composeAndroidPackages {...}.androidsdk`) fails under Lix in
          # flake `outputs` — it must go through a let-binding first. See
          # https://git.lix.systems/lix-project/lix/issues (attr-on-call bug).
          androidSdk = androidComposition.androidsdk;

          /*
            ------------------------------------------------------------------
            Packages
            ------------------------------------------------------------------
          */

          # Versions (see syncscribble/Makefile MAJORVER/MINORVER and
          # android/app/build.gradle versionName).
          linuxVersion = "3.1.0";
          androidVersion = "3.0.24";

          # The nixpkgs cc wrapper enforces -Werror=format-security by default;
          # the vendored ulib/usvg headers contain a PLATFORM_LOG macro that
          # trips it under -Wall. Kept identical in packages and dev shells so
          # `make` in `nix develop` matches `nix build`.
          formatSecurityWorkaround = {
            NIX_CFLAGS_COMPILE = [
              "-Wno-format-security"
              "-Wno-error=format-security"
            ];
          };

          # Linux desktop build (system SDL2 / X11 / OpenGL, GPL-compatible
          # runtime deps only from nixpkgs)
          write-linux = pkgs.stdenv.mkDerivation (
            formatSecurityWorkaround
            // {
              pname = "write";
              version = linuxVersion;

              src = writeSource;

              nativeBuildInputs = [
                pkgs.gnumake
                pkgs.pkg-config
                pkgs.patchelf
                pkgs.xxd
                pkgs.gzip
                pkgs.python3 # embed.py
              ];
              buildInputs = [
                pkgs.SDL2
                pkgs.libX11
                pkgs.libXi
                pkgs.libGL
              ];

              dontConfigure = true;

              # See formatSecurityWorkaround above.
              hardeningDisable = [ "format" ];

              preBuild = generateResources;

              buildPhase = ''
                runHook preBuild
                cd syncscribble
                # USE_SYSTEM_SDL=1: build against the nixpkgs SDL2 instead of the
                # historical SDL fork (its Makefile hard-codes /usr/include paths
                # for dbus/ibus/glib that do not exist on NixOS). `real_tgz`
                # strips the binary and bundles the runtime resources (fonts,
                # Intro.svg, .desktop file) into syncscribble/Release/write*.tar.gz
                make DEBUG=0 USE_SYSTEM_SDL=1 real_tgz
                cd ..
              '';

              installPhase = ''
                runHook preInstall
                mkdir -p $out

                tgz=$(ls syncscribble/Release/write*.tar.gz 2>/dev/null || true)
                if [ -z "$tgz" ] || [ ! -f "$tgz" ]; then
                  echo "Expected release tarball not found (saw: $tgz)" >&2
                  find syncscribble -maxdepth 4 -name '*.tar.gz' >&2 2>/dev/null || true
                  exit 1
                fi

                tar -xzf "$tgz" -C $out

                # The tarball contains a single Write/ directory; flatten it so
                # resources sit next to the executable (SDL_GetBasePath()).
                # Rename the dir first: it contains a file also named `Write`,
                # which would collide with the directory during a direct mv.
                if [ -d "$out/Write" ]; then
                  mv "$out/Write" "$out/Write.bundle"
                  mv "$out/Write.bundle"/* "$out/"
                  rmdir "$out/Write.bundle"
                fi
                chmod +x "$out/Write"

                # On NixOS there is no ldconfig — embed a runpath so the binary
                # finds libSDL2 / libX11 / libXi / libGL in the store.
                patchelf --set-rpath '${
                  lib.makeLibraryPath [
                    pkgs.SDL2
                    pkgs.libX11
                    pkgs.libXi
                    pkgs.libGL
                    pkgs.stdenv.cc.cc.lib
                  ]
                }' "$out/Write"

                mkdir -p "$out/bin"
                ln -sfn "$out/Write" "$out/bin/write"

                runHook postInstall
              '';

              meta = with lib; {
                description = "Cross-platform handwritten notes application by Stylus Labs (Linux build)";
                homepage = "https://github.com/styluslabs/Write";
                # license.of the app proper is AGPL-3.0
                license = licenses.agpl3;
                platforms = [
                  "x86_64-linux"
                  "aarch64-linux"
                ];
                maintainers = [ ];
              };
            }
          );

          # Android APK (debug-signed, per the project's `assembleRelease`).
          # NOTE on the sandbox: Gradle needs to download Maven artifacts
          # (AGP 8.4.0, support-v4, ...) on the first run, which a sandboxed
          # `nix build` cannot do. Either build with networking available, e.g.
          #     nix build .#write-android --option sandbox false
          # or use the dev shell:
          #     nix develop .#android
          #     cd syncscribble/android && ./gww assembleRelease
          write-android = pkgs.stdenv.mkDerivation {
            pname = "write-android";
            version = androidVersion;

            src = androidWriteSource;

            nativeBuildInputs = [
              pkgs.jdk17
              pkgs.gradle
              pkgs.python3
              pkgs.xxd
              pkgs.gzip
              pkgs.which
              pkgs.git
              pkgs.unzip
            ];

            dontConfigure = true;

            preBuild = generateResources;

            buildPhase = ''
              runHook preBuild

              export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
              export ANDROID_SDK_ROOT="${androidSdk}/libexec/android-sdk"
              export ANDROID_NDK_HOME="${androidSdk}/libexec/android-sdk/ndk-bundle"
              export ANDROID_NDK_ROOT="${androidSdk}/libexec/android-sdk/ndk-bundle"
              export JAVA_HOME="${pkgs.jdk17}"

              # Gradle needs writable home directories.
              export HOME="$PWD"
              export GRADLE_USER_HOME="$PWD/.gradle-home"
              mkdir -p "$GRADLE_USER_HOME"

              echo "== Android SDK layout =="
              ls -1 "$ANDROID_HOME"
              ls -1 "$ANDROID_HOME/ndk" || true

              cd syncscribble/android

              # AGP 8.4.0 -> Gradle >= 8.6 (nixpkgs `gradle` is 8.x, fine).
              ${pkgs.gradle}/bin/gradle --no-daemon --console=plain assembleRelease
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out
              apk=$(find . -path '*outputs/apk*' -name '*.apk' | sort | head -1)
              if [ -z "$apk" ] || [ ! -f "$apk" ]; then
                echo "No APK produced!" >&2
                find . -name '*.apk' >&2 2>/dev/null || true
                exit 1
              fi
              echo "Copying $apk"
              cp "$apk" "$out/Write-${androidVersion}.apk"
              ln -sfn "$out/Write-${androidVersion}.apk" "$out/write.apk"
              runHook postInstall
            '';

            meta = with lib; {
              description = "Write for Android (APK, debug-signed build)";
              homepage = "https://github.com/styluslabs/Write";
              license = licenses.agpl3;
              # Android SDK/NDK host tooling is only shipped for x86_64-linux.
              platforms = [ "x86_64-linux" ];
            };
          };

          /*
            ------------------------------------------------------------------
            Formatting (treefmt: single entry point for all formatters)
            ------------------------------------------------------------------
            Legacy C++/Make sources are onboarded incrementally: clang-format
            is configured (.clang-format) and enforced for *changed* files via
            scripts/check quick, but treefmt does not rewrite legacy C++ yet,
            to keep this patch free of a giant mechanical reformat. Everything
            else (Nix, shell, Python, YAML/JSON/Markdown) is formatted.
            ------------------------------------------------------------------
          */
          treefmtEval = treefmt-nix.lib.evalModule pkgs {
            projectRootFile = "flake.nix";
            programs = {
              nixfmt.enable = true;
              shfmt.enable = true;
              # keep Makefile recipe tabs intact: no formatter for Make
              prettier = {
                enable = true;
                includes = [
                  "*.md"
                  "*.yml"
                  "*.yaml"
                  "*.json"
                ];
                excludes = [
                  # canonical documents / compatibility fixtures: never rewrite
                  "scribbletest/*"
                  "scribbleres/Intro.svg"
                ];
              };
              ruff.format = true;
            };
            settings = {
              global = {
                excludes = [
                  # vendored / submodule / generated trees are never formatted
                  "SDL/*"
                  "ugui/*"
                  "ulib/*"
                  "usvg/*"
                  "nanovgXC/*"
                  "pugixml/*"
                  "miniz/*"
                  "stb/*"
                  # legacy Xcode project metadata (incremental onboarding)
                  "xcode/*"
                  # legacy app resources & scripts are onboarded incrementally;
                  # new engineering tooling under scripts/ IS formatted
                  "scribbleres/*"
                  "README.md"
                  "syncscribble/CppProperties.json"
                  ".envrc"
                  # canonical note documents and test fixtures
                  "scribbletest/*"
                  "*.svg"
                  "*.svgz"
                ];
              };
              formatter.shfmt.options = [
                "-s"
                "-ln"
                "bash"
                "-w"
              ];
            };
          };

          /*
            ------------------------------------------------------------------
            Developer tool sets
            ------------------------------------------------------------------
          */

          # Quick-check tooling shared by CI and the dev shell.
          quickTools = [
            pkgs.shellcheck
            pkgs.shfmt
            pkgs.actionlint
            pkgs.gitleaks
            pkgs.nixfmt-rfc-style
            pkgs.statix
            pkgs.deadnix
            pkgs.treefmt # not strictly needed in-shell (nix fmt), useful anyway
          ];

          # C++ static analysis on a real compile database (see scripts/check static).
          cppTools = [
            pkgs.clang-tools # clang-format, clang-tidy
            pkgs.bear # compile_commands.json capture from the make build
          ];

          # Common Linux build/dev tools (no Android).
          linuxTools = [
            pkgs.gcc
            pkgs.gnumake
            pkgs.pkg-config
            pkgs.SDL2
            # nixpkgs' SDL2 is sdl2-compat, which dlopens the real SDL3 at
            # runtime — without this the app aborts with
            # "Failed loading SDL3 library."
            (lib.hiPrio pkgs.sdl3)
            pkgs.libX11
            pkgs.libXi
            pkgs.libGL
            pkgs.python3
            pkgs.xxd
            pkgs.gzip
            pkgs.patchelf
            # developer utilities
            pkgs.git
            pkgs.file
            pkgs.jq
            pkgs.ripgrep
            pkgs.fd
            pkgs.which
          ];

          # Android-only tooling (x86_64-linux).
          androidTools = [
            pkgs.jdk17
            pkgs.gradle
            pkgs.cmake
            androidSdk
          ];

          # Run the pinned local hooks (defined here, generated into
          # .pre-commit-config.yaml by `nix develop -c pre-commit-install`).
          # One source of truth: never edit .pre-commit-config.yaml by hand.
          preCommitCheck = pre-commit-hooks.lib.${system}.run {
            src = self;
            hooks = {
              check-merge-conflicts.enable = true;
              check-added-large-files.enable = true;
              mixed-line-endings = {
                enable = true;
                description = "No CRLF line endings in tracked text files";
              };
              treefmt = {
                enable = true;
                name = "treefmt";
                description = "Format staged files with the flake's treefmt config (same as nix fmt)";
                # fail-on-change: rewrites stay UNSTAGED for review; nothing is
                # auto-added, so partially staged files cannot be silently changed
                entry = "${lib.getExe treefmtEval.config.build.wrapper} --fail-on-change";
                pass_filenames = true;
                require_serial = true;
              };
              shellcheck = {
                enable = true;
                # new engineering scripts only; legacy scripts (scribbleres/,
                # syncscribble/android/*) are onboarded incrementally and are
                # ShellChecked by scripts/check quick when they change
                files = "^scripts/.*\\.sh$";
              };
              gitleaks = {
                enable = true;
                name = "gitleaks";
                description = "Scan staged content for secrets (pinned via flake lock)";
                entry = "${pkgs.gitleaks}/bin/gitleaks git --pre-commit --staged --redact --verbose";
                pass_filenames = false;
                # exclusions (if ever needed) must be narrow and owner-reviewed
                # via .gitleaks.toml, never a blanket allowlist
              };
              linux-smoke = {
                enable = true;
                name = "linux-smoke";
                description = "Run the Linux build, sanitized regression suite, and app smoke test before push";
                entry = "./scripts/check linux";
                pass_filenames = false;
                stages = [ "pre-push" ];
              };
            };
          };
        in
        {
          packages = {
            inherit write-linux;
          }
          // lib.optionalAttrs (system == "x86_64-linux") {
            inherit write-android;
          };

          formatter = treefmtEval.config.build.wrapper;

          checks = {
            formatting = treefmtEval.config.build.check self;
            pre-commit = preCommitCheck;
            # `nix flake check` evaluates+builds these; write-linux doubles as
            # the "clean build from spliced source" check (submodules included).
            inherit write-linux;
          };

          devShells = {
            # Lightweight: Linux build tools + quick checks, no Android SDK.
            # This is what `nix develop .#linux` (and CI local checks) use.
            linux = pkgs.mkShell (
              formatSecurityWorkaround
              // {
                name = "write-linux-dev";
                packages = linuxTools ++ quickTools ++ cppTools ++ preCommitCheck.enabledPackages;
                # let the test binary find libSDL3 for sdl2-compat
                LD_LIBRARY_PATH = "${lib.getLib pkgs.sdl3}/lib";
                shellHook = ''
                  ${preCommitCheck.shellHook}
                  if [ ! -f ugui/ugui.h ] || [ ! -f SDL/include/SDL.h ]; then
                      echo "Initializing git submodules in the working tree..."
                      git submodule update --init --recursive
                    fi
                '';
              }
            );

            # Everything: Linux + Android SDK/NDK + JDK 17 + Gradle.
            default = pkgs.mkShell (
              formatSecurityWorkaround
              // {
                name = "write-dev";
                packages =
                  linuxTools ++ quickTools ++ cppTools ++ lib.optionals (system == "x86_64-linux") androidTools;

                shellHook = ''
                  ${preCommitCheck.shellHook}
                  # Android environment (only meaningful on x86_64-linux)
                    ${lib.optionalString (system == "x86_64-linux") ''
                          export JAVA_HOME="${pkgs.jdk17}"
                          export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
                          export ANDROID_SDK_ROOT="${androidSdk}/libexec/android-sdk"
                          export ANDROID_NDK_HOME="${androidSdk}/libexec/android-sdk/ndk-bundle"
                      export ANDROID_NDK_ROOT="${androidSdk}/libexec/android-sdk/ndk-bundle"
                      export PATH="${androidSdk}/libexec/android-sdk/platform-tools:${androidSdk}/bin:$PATH"
                      export WRITE_ANDROID_SDL="${androidSdl}"
                          echo "--- Write dev shell (Android tools at \$ANDROID_HOME) ---"
                    ''}
                    export LD_LIBRARY_PATH="${lib.getLib pkgs.sdl3}/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

                    # The Nix builds fetch their own copies of the submodules, but if
                    # you run `make` manually against the working tree the submodules
                    # are still uninitialized. Initialize them on first use.
                    if [ ! -f ugui/ugui.h ] || [ ! -f SDL/include/SDL.h ]; then
                      echo "Initializing git submodules in the working tree..."
                      git submodule update --init --recursive
                    fi
                '';
              }
            );

            # Android-only shell (smaller than default on CI).
            android = pkgs.mkShell {
              name = "write-android-dev";
              packages = lib.optionals (system == "x86_64-linux") androidTools ++ [
                pkgs.python3
                pkgs.xxd
                pkgs.gzip
                pkgs.git
                pkgs.which
                pkgs.unzip
              ];
              shellHook = ''
                ${lib.optionalString (system == "x86_64-linux") ''
                  export JAVA_HOME="${pkgs.jdk17}"
                  export ANDROID_HOME="${androidSdk}/libexec/android-sdk"
                  export ANDROID_SDK_ROOT="${androidSdk}/libexec/android-sdk"
                  export ANDROID_NDK_HOME="${androidSdk}/libexec/android-sdk/ndk-bundle"
                  export ANDROID_NDK_ROOT="${androidSdk}/libexec/android-sdk/ndk-bundle"
                  export PATH="${androidSdk}/libexec/android-sdk/platform-tools:${androidSdk}/bin:$PATH"
                  export WRITE_ANDROID_SDL="${androidSdl}"
                ''}
                if [ ! -f ugui/ugui.h ] || [ ! -f SDL/include/SDL.h ]; then
                  echo "Initializing git submodules in the working tree..."
                  git submodule update --init --recursive
                fi
              '';
            };
          };
        }
      );
}
