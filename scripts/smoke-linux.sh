#!/usr/bin/env bash
# Bounded application smoke test: initialize Write's real SDL/UI stack in an
# isolated home, open the bundled SVG document, and exit cleanly. This is not a
# substitute for the regression suite's save/reopen assertions.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
BIN="${REPO_ROOT}/syncscribble/Debug/Write"

if [[ ${1:-} == "--bin" ]]; then
  BIN="$2"
  shift 2
fi
[[ $# -eq 0 ]] || {
  echo "usage: $0 [--bin PATH]" >&2
  exit 64
}
[[ -x $BIN ]] || {
  echo "smoke-linux.sh: binary not executable: $BIN" >&2
  exit 1
}

HOME_DIR="$(mktemp -d /tmp/write-smoke-home.XXXXXX)"
LOG_DIR="$(mktemp -d /tmp/write-smoke-log.XXXXXX)"
trap 'rm -rf "$HOME_DIR" "$LOG_DIR"' EXIT

set +e
timeout --signal=KILL 60 env \
  HOME="$HOME_DIR" \
  SDL_VIDEODRIVER=dummy \
  "$BIN" --glRender=0 --exit "${REPO_ROOT}/scribbleres/Intro.svg" >"$LOG_DIR/smoke.log" 2>&1
STATUS=$?
set -e

if [[ $STATUS -eq 124 || $STATUS -eq 137 ]]; then
  cat "$LOG_DIR/smoke.log" >&2
  echo "smoke-linux.sh: timed out" >&2
  exit 1
fi
if [[ $STATUS -ne 0 ]]; then
  cat "$LOG_DIR/smoke.log" >&2
  echo "smoke-linux.sh: application exited with $STATUS" >&2
  exit 1
fi

echo "smoke-linux.sh: OK"
