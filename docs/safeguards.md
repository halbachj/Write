# Engineering Safeguards

## Required checks

CI is authoritative. Required jobs are `quality`, `linux-regression`,
`linux-smoke`, `static-analysis`, `android-build-lint`, and the always-evaluated
aggregate `ci-gate`. `ci-gate` fails for every dependency result except
`success`, including failure, cancellation, absence, and skip.

Local equivalents:

```sh
nix develop -c ./scripts/check quick
nix develop -c ./scripts/check linux
nix develop .#android -c ./scripts/check android
```

`scripts/run-tests.sh` requires 17 native executions: 16 existing regression
cases plus one self-contained document-integrity corpus. It writes a machine
readable result file, uses conventional process statuses, requires isolated
output, and rejects crashes, timeouts, missing reports, zero/wrong test counts,
and sanitizer reports outside its narrow third-party exception.

The corpus verifies open/edit/save/reopen behavior in HTML, SVG, and SVGZ using
real loader/serializer paths; vector and pressure strokes, multi-page structure,
bookmark/link behavior, imported unknown SVG attributes, and failed-save recovery
are exercised. It does **not** claim compatibility with older Write releases;
it proves only current-loader round trips for the synthetic corpus.

## Visible legacy debt

The runner permits exactly thumbnail mismatch `test5` after tolerant comparison.
It is a documented transparent-ruling blend difference (not missing SVG ink or
metadata) between rendering stacks. It remains printed and artifacted. Any new
thumbnail mismatch fails. SVG content comparisons remain exact and blocking.

UBSan reports only for two intentional unaligned accesses in pinned third-party
`miniz/miniz_tdef.c` are visible but non-fatal. Any sanitizer report from Write or
another dependency fails. Removing either narrow exception needs owner review.

## Exceptions and reviews

Do not make a failing check green by deleting tests, lowering expectations,
widening exclusions, disabling lint, or silently changing goldens. A necessary
exception must name the precise scope, rationale, owner/reviewer, expiry or
follow-up issue, and verification that data loss is not being accepted.

Changes to CI, hooks, baselines, suppressions, generated expected output,
dependency pins/submodules, SVG/SVGZ serialization, save/recovery, input, or
rendering require CODEOWNERS review.

## Device validation (manual, not automated coverage)

Before release or a material input/rendering change, test on an Android tablet
with an active stylus:

1. Pressure response and stroke shape across slow/fast strokes.
2. Palm rejection, touch pan/zoom, stylus-button behavior, erasing, selection,
   undo/redo, and ruled reflow.
3. Perceived pen latency while opening/saving a representative synthetic note.
4. Rotation, background/foreground lifecycle, and interrupted-save behavior.
5. Tablet and phone layout/navigation. Android phone is secondary but must not
   regress basic review/light-edit flows.
6. Linux open/edit/save/reopen of an SVGZ copy in an isolated directory.

No Android emulator smoke is currently claimed: the custom-rendered UI has no
reliable semantic UI automation or input-replay hook yet, and simply starting an
APK is not a save/reopen test. Smallest follow-up: add an instrumented bridge that
loads a synthetic document, performs one deterministic edit, saves, and reopens
inside app storage; then add an emulator job that asserts its report.

## Branch protection

The committed workflow and CODEOWNERS file do not prove repository enforcement.
Branch protection is **awaiting administrator action** until an administrator
verifies it remotely. On the actual default branch, configure:

1. Require pull requests and the `ci-gate` status check.
2. Require CODEOWNERS review for the paths above and dismiss stale approvals.
3. Block force pushes and branch deletion; do not grant worker bypass.
4. Apply the same rules to merge-queue/merge-group validation when enabled.

After configuring, record a real PR showing a failed `ci-gate` blocks merge.

## Pin review

Nix inputs are locked in `flake.lock`; submodule revisions are explicitly listed
in `flake.nix`; GitHub Actions use immutable revisions resolved from their tagged
upstreams. Pin changes require owner review, `nix flake check --no-update-lock-file`,
and a review of the resulting lock/action diff. CI never updates pins or locks.
