#!/usr/bin/env bash
# Run the Write native regression suite headlessly and enforce honest results:
#   - conventional exit status from the test binary (0 ok / 1 test failures /
#     2 thumbnail-only failures / 3 execution error)
#   - expected test count executed (a run that executes nothing cannot pass)
#   - crash and timeout detection
#   - sanitizer findings fail the run, except the narrowly documented list below
#   - thumbnail diffs are compared against an explicit, reviewed baseline list;
#     any NEW thumbnail diff fails (legacy renderer debt must stay visible)
#
# Usage: scripts/run-tests.sh [--bin PATH] [--out DIR] [--timeout SECS]
#         [--expected N] [--baseline-thumb-failures a,b]
# Env: SCRIBBLE_TESTER (optional) alternative launcher (e.g. "xvfb-run -a")
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

BIN="${REPO_ROOT}/syncscribble/Debug/Write"
OUT=""
TIMEOUT=600
EXPECTED_TESTS=17
BASELINE_THUMB_FAILS="5"

while [[ $# -gt 0 ]]; do
  case "$1" in
  --bin)
    BIN="$2"
    shift 2
    ;;
  --out)
    OUT="$2"
    shift 2
    ;;
  --timeout)
    TIMEOUT="$2"
    shift 2
    ;;
  --expected)
    EXPECTED_TESTS="$2"
    shift 2
    ;;
  --baseline-thumb-failures)
    BASELINE_THUMB_FAILS="$2"
    shift 2
    ;;
  *)
    echo "run-tests.sh: unknown argument: $1" >&2
    exit 64
    ;;
  esac
done

# Known UBSan findings in vendored third-party code, kept visible in logs but
# non-fatal: miniz 2.0.8 intentionally performs unaligned loads/stores.
# Anything else (including any finding in Write's own code) fails the run.
KNOWN_UBSAN_RE='^[^:]*miniz/miniz_tdef\.c:[0-9]+:[0-9]+: runtime error: (load of|store to) misaligned address'

fail() {
  echo "run-tests.sh: FAIL: $*" >&2
  exit 1
}

[[ -x $BIN ]] || fail "test binary not found/executable: $BIN (build it first)"

if [[ -z $OUT ]]; then
  OUT="$(mktemp -d /tmp/write-tests.XXXXXX)"
  KEEP_OUT=0
else
  mkdir -p "$OUT"
  KEEP_OUT=1
fi
WORK_HOME="$(mktemp -d /tmp/write-testhome.XXXXXX)"
trap '[[ $KEEP_OUT -eq 0 ]] && rm -rf "$OUT"; rm -rf "$WORK_HOME"' EXIT

echo "run-tests.sh: binary=$BIN"
echo "run-tests.sh: outdir=$OUT (home=$WORK_HOME)"
echo "run-tests.sh: revision=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown) dirty=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"

ASAN_OPTIONS="detect_leaks=0:abort_on_error=1"
UBSAN_OPTIONS="print_stacktrace=1"
export ASAN_OPTIONS UBSAN_OPTIONS

rm -f "$OUT/test-summary.txt"
set +e
timeout --signal=KILL "$TIMEOUT" env \
  HOME="$WORK_HOME" \
  SCRIBBLE_TEST_OUT="$OUT" \
  SDL_VIDEODRIVER=dummy \
  ${SCRIBBLE_TESTER:+$SCRIBBLE_TESTER} \
  "$BIN" --glRender=0 --test >"$OUT/test-run.log" 2>&1
STATUS=$?
set -e

echo "run-tests.sh: process status: $STATUS"
if [[ $STATUS -eq 124 || $STATUS -eq 137 ]]; then
  fail "test process timed out (or was killed) after ${TIMEOUT}s; see $OUT/test-run.log"
fi
if [[ $STATUS -ge 128 ]]; then
  fail "test process died from signal $((STATUS - 128)) (crash/ASan abort); see $OUT/test-run.log"
fi
if [[ $STATUS -eq 127 ]]; then
  fail "test process could not be started; see $OUT/test-run.log"
fi
if [[ $STATUS -eq 3 ]]; then
  fail "test-execution error (wrong number of tests executed); see $OUT/test-run.log"
fi
if [[ $STATUS -ne 0 && $STATUS -ne 1 && $STATUS -ne 2 ]]; then
  fail "unexpected test process status $STATUS; see $OUT/test-run.log"
fi

SUMMARY="$OUT/test-summary.txt"
[[ -f $SUMMARY ]] || fail "no test-summary.txt produced (did the runner execute?); see $OUT/test-run.log"

executed="$(sed -n 's/^tests_executed=//p' "$SUMMARY")"
tests_failed="$(sed -n 's/^tests_failed=//p' "$SUMMARY")"
thumb_failed="$(sed -n 's/^thumbnail_failed=//p' "$SUMMARY")"
failed_list="$(sed -n 's/^failed_tests=//p' "$SUMMARY")"
thumb_list="$(sed -n 's/^thumbnail_failures=//p' "$SUMMARY")"

[[ $executed == "$EXPECTED_TESTS" ]] ||
  fail "expected $EXPECTED_TESTS tests to execute, but summary reports '$executed'; see $OUT/test-summary.txt"
[[ $tests_failed == "0" ]] ||
  fail "$tests_failed content test(s) failed: ${failed_list:-?}; see $OUT/test-summary.txt"

# thumbnail failures: only the explicitly reviewed baseline may remain
if [[ $thumb_failed != "0" ]]; then
  IFS=',' read -ra BASE <<<"$BASELINE_THUMB_FAILS"
  declare -A base_set=()
  for t in "${BASE[@]}"; do [[ -n $t ]] && base_set["$t"]=1; done
  IFS=',' read -ra ACT <<<"$thumb_list"
  for t in "${ACT[@]}"; do
    [[ -n $t && -n ${base_set[$t]:-} ]] ||
      fail "new thumbnail mismatch in test $t (baseline: ${BASELINE_THUMB_FAILS:-none}); see $OUT/test{,_ref,_diff}*.png"
  done
  echo "run-tests.sh: WARNING: known thumbnail debt remains: tests $thumb_list (see docs/safeguards.md)"
fi

# sanitizer findings (outside the narrow known list) must fail the job
if grep -E 'runtime error:' "$OUT/test-run.log" | grep -Ev "$KNOWN_UBSAN_RE" | grep -q .; then
  grep -E 'runtime error:' "$OUT/test-run.log" | grep -Ev "$KNOWN_UBSAN_RE" | head -20 >&2
  fail "UBSan reported errors outside the documented known list; see $OUT/test-run.log"
fi

if [[ $STATUS -eq 2 ]]; then
  echo "run-tests.sh: OK (with documented thumbnail baseline debt)"
else
  echo "run-tests.sh: OK - all $executed tests passed, no unexpected sanitizer findings"
fi
exit 0
