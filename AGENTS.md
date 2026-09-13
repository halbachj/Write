# Write Repository Instructions

## Repository-first workflow

1. Read the relevant code and this repository's guidance before changing it.
2. Treat the current checkout, including submodule gitlinks, as the source of truth.
3. Preserve unrelated staged, unstaged, and untracked work. Do not reset, clean,
   rebase, force-push, or rewrite generated/golden files as a convenience.
4. Use disposable directories or worktrees for failure injection and destructive
   experiments. Never use real note libraries, credentials, signing keys, or
   private note content as test data.

## Product and data constraints

- Preserve Write's pen-first C++ architecture and canonical SVG/SVGZ documents.
- Prioritize Android tablets and Linux. Keep work off real-time pen/input paths
  unless the change is specifically about that path and is measured.
- Do not silently discard ink, metadata, unknown SVG content, or acknowledged
  saved content. Do not replace tests, lower expectations, widen exclusions, or
  update goldens merely to make a check green.
- Serialization, save/recovery, renderer/input, compatibility fixtures,
  submodule/dependency pins, CI, hooks, baselines, and suppressions require
  explicit owner review.

## Required verification

Run the narrowest applicable checks and report their exact commands/results:

```sh
nix fmt
nix flake check --no-update-lock-file
nix develop -c ./scripts/check quick
nix develop -c ./scripts/check linux
nix develop -c ./scripts/check android
```

`linux` includes sanitized native regression/document-integrity tests and a
headless app smoke test. `android` must be run inside `nix develop .#android`.
Hooks are convenience only; skipping a local hook never authorizes an unverified
merge. CI and required review remain authoritative.

## Truthful completion

State what changed, the tested revision and dirty-tree status, commands actually
run, observed results, and remaining risks/blocks. Never claim a build, test,
Android behavior, CI run, or branch protection was verified unless it actually
ran and succeeded.
