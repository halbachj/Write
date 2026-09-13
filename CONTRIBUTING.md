# Contributing to Write

Write is an AGPL-3.0, C++ handwritten-note application. Preserve its pen-first
interaction model and SVG/SVGZ documents. See `AGENTS.md` and
`docs/safeguards.md` before changing document, input, rendering, or safeguards.

## Setup

```sh
git clone --recurse-submodules <your-fork-url>
cd Write
git submodule update --init --recursive
nix develop
```

The flake lock pins Nix tools; application dependencies remain the repository's
Make/Gradle builds. Gradle downloads Maven artifacts on first use, so an Android
build started in a Nix shell is reproducible in tool versions, not hermetic.

Useful shells:

```sh
nix develop                 # tools plus Android SDK/NDK on x86_64 Linux
nix develop .#linux         # Linux build/test tools
nix develop .#android       # Android SDK/NDK, JDK 17, Gradle
```

## Checks

```sh
nix fmt
nix flake check --no-update-lock-file
nix develop -c ./scripts/check quick
nix develop -c ./scripts/check linux
nix develop .#android -c ./scripts/check android
```

`quick` is check-only: it does not update the lock file, format files, or
regenerate expected outputs. `linux` builds `DEBUG=1`, which enables ASan and
UBSan in the existing Makefile, then runs the native suite headlessly with
isolated output. A zero-test run, missing report, crash, timeout, missing binary,
or unexpected sanitizer finding fails. Test artifacts are in the runner output
directory when one is supplied.

The regression runner has one visible thumbnail baseline (`test5`): a legacy
transparent-ruling blend difference across renderer stacks. SVG/document content
remains exact and blocking; a new thumbnail mismatch fails. See
`docs/safeguards.md` before altering that baseline.

## Hooks

Install hooks from the flake-defined source of truth:

```sh
nix develop
nix develop -c pre-commit run --all-files
```

Entering `nix develop` installs/updates the repository-local Nix-managed hooks.
The generated `.pre-commit-config.yaml` is not a hand-maintained configuration.
Hooks run staged-file hygiene, formatting, conflict checks, and Gitleaks. They do
not auto-stage edits, run Android builds, or replace CI. To run the local
pre-push smoke set, use `nix develop -c ./scripts/check linux`; the same command
is installed as the local pre-push hook. If a pre-existing local hooks path
prevents installation, do not overwrite it: run the command explicitly and ask
the repository maintainer to reconcile the hook manager.

## Formatting and analysis

`nix fmt` owns Nix, shell, Python, workflow, JSON/YAML, and Markdown formatting.
Submodules, generated resources, canonical SVG/SVGZ documents, and legacy source
trees are explicitly excluded from automatic rewriting. C++ formatting is being
onboarded separately: `.clang-format` is supplied for new code, but a dedicated
mechanical patch is required before enforcing it on legacy files.

`nix develop -c ./scripts/check static` captures a real compile database with
Bear and runs curated clang-tidy analyzer checks on document/save, stroke, and
input code. Do not substitute a guessed compilation database.

## Android troubleshooting

`syncscribble/android/app/build.gradle` pins NDK `26.3.11579264`; the flake
provides that exact version, JDK 17, Gradle, platform 30, and build-tools 34.0.0.
Lint is explicit (`lintDebug`) and `abortOnError` is enabled. Do not add a broad
lint baseline or disable errors; discuss a narrow, documented exception first.

## Pull requests

Use the PR template. Include exact verification evidence, compatibility and pen
latency implications, and residual risk. Changes to safeguards, suppressions,
expected outputs, dependency pins, or critical document/input behavior need an
owner review. Do not bypass local hooks or CI as a merge-policy workaround.
