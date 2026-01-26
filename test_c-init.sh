#!/usr/bin/env bash

set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
RAW_CINIT="${1:-$ROOT/c-init.sh}"
# Resolve to absolute path if relative
if [[ "$RAW_CINIT" = /* ]]; then
  CINIT="$RAW_CINIT"
else
  CINIT="$(pwd)/$RAW_CINIT"
fi

LAST_OUT=""
LAST_ERR=""
LAST_CODE=0

GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

TEST_NAME=""
CURRENT_FAILED=0
FAIL_COUNT=0
TMP_DIRS=()

cleanup() {
  if [ "$FAIL_COUNT" -ne 0 ]; then
    return 0
  fi
  local dir
  for dir in "${TMP_DIRS[@]}"; do
    rm -rf "$dir"
  done
}

trap cleanup EXIT

test_begin() {
  TEST_NAME="$1"
  CURRENT_FAILED=0
  printf "TEST: %s\n" "$TEST_NAME"
}

test_ok() {
  if [ "$CURRENT_FAILED" -eq 0 ]; then
    printf "  ${GREEN}✔︎${RESET} pass\n"
  fi
}

fail() {
  CURRENT_FAILED=1
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  ${RED}⨯${RESET} %s: %s\n" "$TEST_NAME" "$*" >&2
  return 0
}

run() {
  local LAST_OUT_FILE=$(mktemp)
  local LAST_ERR_FILE=$(mktemp)
  set +e
  "$@" >"$LAST_OUT_FILE" 2>"$LAST_ERR_FILE"
  LAST_CODE=$?
  set -e
  LAST_OUT=$(cat "$LAST_OUT_FILE")
  LAST_ERR=$(cat "$LAST_ERR_FILE")
  COMBINED="$LAST_OUT$LAST_ERR"
  rm -f "$LAST_OUT_FILE" "$LAST_ERR_FILE"
}

assert_code() {
  local expected="$1"
  [ "$LAST_CODE" -eq "$expected" ] || fail "expected exit $expected, got $LAST_CODE"
}

assert_contains() {
  local hay="$1"
  local needle="$2"
  case "$hay" in
    *"$needle"*) ;;
    *) fail "expected to contain: $needle" ;;
  esac
}

assert_file() {
  local path="$1"
  [ -f "$path" ] || fail "expected file: $path"
}

assert_dir() {
  local path="$1"
  [ -d "$path" ] || fail "expected dir: $path"
}

assert_missing() {
  local path="$1"
  [ ! -e "$path" ] || fail "expected missing: $path"
}

# 1) --help should exit 0 and print usage
test_begin "--help prints usage and exits 0"
run "$CINIT" --help
assert_code 0
assert_contains "$LAST_OUT" "Usage:"
test_ok

# 2) Unknown flag should exit 1 and print help
test_begin "unknown flag exits 1 and prints help"
run "$CINIT" --garbage
assert_code 1
# Both print "unknown option" and "--garbage" though case/quotes vary
COMBINED="$LAST_OUT$LAST_ERR"
assert_contains "$(echo "$COMBINED" | tr '[:upper:]' '[:lower:]')" "unknown option"
assert_contains "$COMBINED" "--garbage"
assert_contains "$COMBINED" "Usage:"
test_ok

# 3) Create project with no hello and no git
test_begin "create project with --no-hello --no-git"
TMPDIR=$(mktemp -d)
TMP_DIRS+=("$TMPDIR")
PROJ="$TMPDIR/proj"
run "$CINIT" --cc gcc -s strict --no-hello --no-git "$PROJ"
assert_code 0
assert_dir "$PROJ/src"
assert_dir "$PROJ/include"
assert_dir "$PROJ/target"
assert_file "$PROJ/Makefile"
assert_file "$PROJ/compile_flags.txt"
assert_missing "$PROJ/src/main.c"
test_ok

# 4) Non-empty directory should fail without --force
test_begin "non-empty dir fails without --force"
TMPDIR2=$(mktemp -d)
TMP_DIRS+=("$TMPDIR2")
PROJ2="$TMPDIR2/proj"
mkdir -p "$PROJ2"
printf "x" > "$PROJ2/file.txt"
run "$CINIT" --no-git "$PROJ2"
assert_code 1
assert_contains "$LAST_ERR" "not empty"
test_ok

# 5) Linter strictness override should affect .clang-tidy
test_begin "linter strictness override creates strictest .clang-tidy"
TMPDIR3=$(mktemp -d)
TMP_DIRS+=("$TMPDIR3")
PROJ3="$TMPDIR3/proj"
run "$CINIT" --no-git --linter-strictness strictest "$PROJ3"
assert_code 0
assert_file "$PROJ3/.clang-tidy"
assert_contains "$(cat "$PROJ3/.clang-tidy")" "modernize"
test_ok

# 6) Interactive mode creates project
test_begin "interactive mode creates project"
TMPDIR4=$(mktemp -d)
TMP_DIRS+=("$TMPDIR4")
cd "$TMPDIR4"
# Give a name for the prompt
run "$CINIT" -i <<< "interactive_proj"
assert_code 0
assert_dir "interactive_proj"
assert_file "interactive_proj/src/main.c"
assert_dir "interactive_proj/.git"
cd "$ROOT"
test_ok

# 7) Interactive mode refuses overwrite
test_begin "interactive mode refuses overwrite"
TMPDIR5=$(mktemp -d)
TMP_DIRS+=("$TMPDIR5")
cd "$TMPDIR5"
mkdir -p "existing"
touch "existing/file"

# Input "existing" then "0" (No) for overwrite
run "$CINIT" -i <<< "$(printf "existing\n0\n")"
assert_code 1
assert_contains "$COMBINED" "Exiting..."
cd "$ROOT"
test_ok


if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
