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

ACUTEST_TMP=$(mktemp -d)
TMP_DIRS+=("$ACUTEST_TMP")
ACUTEST_BIN="$ACUTEST_TMP/bin"
mkdir -p "$ACUTEST_BIN"
ACUTEST_CACHE="$ACUTEST_TMP/acutest.h"

cat <<'EOF' > "$ACUTEST_BIN/curl"
#!/usr/bin/env bash
set -euo pipefail
OUT=""
URL=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o)
      OUT="$2"
      shift 2
      ;;
    *)
      if [[ "$1" != -* ]]; then
        URL="$1"
      fi
      shift
      ;;
  esac
done

[ -n "$OUT" ] || { echo "curl stub missing -o" >&2; exit 2; }
[ -n "$URL" ] || { echo "curl stub missing URL" >&2; exit 2; }

if [ ! -f "__ACUTEST_CACHE__" ]; then
  /usr/bin/curl -fsSL "$URL" -o "__ACUTEST_CACHE__"
fi

cat "__ACUTEST_CACHE__" > "$OUT"
EOF
sed -i "" "s|__ACUTEST_CACHE__|$ACUTEST_CACHE|g" "$ACUTEST_BIN/curl"
chmod +x "$ACUTEST_BIN/curl"

export PATH="$ACUTEST_BIN:$PATH"

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
assert_dir "$PROJ/tests"
assert_file "$PROJ/tests/test-deps/acutest.h"
assert_file "$PROJ/tests/compile_flags.txt"
assert_contains "$(cat "$PROJ/Makefile")" "sanitize:"
assert_contains "$(cat "$PROJ/README.md")" "make sanitize"
test_ok

# 3c) --no-commit skips initial commit
test_begin "--no-commit skips initial commit"
TMPDIR_NO_COMMIT=$(mktemp -d)
TMP_DIRS+=("$TMPDIR_NO_COMMIT")
PROJ_NO_COMMIT="$TMPDIR_NO_COMMIT/proj"
run "$CINIT" --no-commit "$PROJ_NO_COMMIT"
assert_code 0
assert_dir "$PROJ_NO_COMMIT/.git"
run git -C "$PROJ_NO_COMMIT" rev-parse --verify HEAD
if [ "$LAST_CODE" -eq 0 ]; then
  fail "expected no initial commit"
fi
test_ok

# 3b) --no-tests skips tests and vendoring
test_begin "--no-tests skips tests folder"
TMPDIR_NO_TESTS=$(mktemp -d)
TMP_DIRS+=("$TMPDIR_NO_TESTS")
PROJ_NO_TESTS="$TMPDIR_NO_TESTS/proj"
run "$CINIT" --no-tests "$PROJ_NO_TESTS"
assert_code 0
assert_missing "$PROJ_NO_TESTS/tests"
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

# 7b) Interactive mode accepts overwrite
test_begin "interactive mode accepts overwrite"
TMPDIR5B=$(mktemp -d)
TMP_DIRS+=("$TMPDIR5B")
cd "$TMPDIR5B"
mkdir -p "existing"
touch "existing/file"

# Input "existing" then "1" (Yes) for overwrite
run "$CINIT" -i <<< "$(printf "existing\n1\n")"
assert_code 0
assert_dir "existing/src"
assert_file "existing/Makefile"
cd "$ROOT"
test_ok

# 8) GCC flags are correctly generated
test_begin "GCC flags are correctly generated"
TMPDIR6=$(mktemp -d)
TMP_DIRS+=("$TMPDIR6")
PROJ6="$TMPDIR6/proj"
run "$CINIT" --cc gcc -s strictest "$PROJ6"
assert_code 0
assert_file "$PROJ6/compile_flags.txt"
# Check for a GCC-specific flag like -Wlogical-op or -Wduplicated-cond
assert_contains "$(cat "$PROJ6/compile_flags.txt")" "-Wlogical-op"
assert_contains "$(cat "$PROJ6/compile_flags.txt")" "-Wduplicated-cond"
test_ok

# 9) Compilation tests for all strictness levels and both compilers
for cc in clang gcc; do
  for s in loose strict strictest; do
    test_begin "compilation: $cc with -s $s"
    TMPDIR_COMP=$(mktemp -d)
    TMP_DIRS+=("$TMPDIR_COMP")
    PROJ_COMP="$TMPDIR_COMP/proj"
    
    # Run c-init
    run "$CINIT" --cc "$cc" -s "$s" "$PROJ_COMP"
    assert_code 0
    # Check that it mentions the compiler (could be gcc, clang, or gcc-15 etc)
    assert_contains "$LAST_OUT" "using "
    
    # Compile using the generated Makefile
    # We use -C to run make in the project directory
    run make -C "$PROJ_COMP"
    assert_code 0
    assert_file "$PROJ_COMP/target/debug/proj"
    
    # Run the compiled binary
    run "$PROJ_COMP/target/debug/proj"
    assert_code 0
    assert_contains "$LAST_OUT" "Hello from proj!"
    
    test_ok
  done
done

# 9b) make test builds and runs tests
test_begin "make test builds and runs tests"
TMPDIR_TESTS=$(mktemp -d)
TMP_DIRS+=("$TMPDIR_TESTS")
PROJ_TESTS="$TMPDIR_TESTS/proj"
run "$CINIT" --no-git "$PROJ_TESTS"
assert_code 0
run make -C "$PROJ_TESTS" test
assert_code 0
assert_file "$PROJ_TESTS/target/debug/tests/proj_tests"
test_ok

# 10) 'make run' with arguments
test_begin "'make run' passes arguments"
TMPDIR_ARGS=$(mktemp -d)
TMP_DIRS+=("$TMPDIR_ARGS")
PROJ_ARGS="$TMPDIR_ARGS/proj"

./c-init.sh --no-git "$PROJ_ARGS" > /dev/null
# Replace main.c with one that prints args
cat <<EOF > "$PROJ_ARGS/src/main.c"
#include <stdio.h>
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) printf("ARG:%s\n", argv[i]);
    return 0;
}
EOF

run make -C "$PROJ_ARGS" run foo bar baz
assert_code 0
assert_contains "$LAST_OUT" "ARG:foo"
assert_contains "$LAST_OUT" "ARG:bar"
assert_contains "$LAST_OUT" "ARG:baz"
test_ok

# 11) 'make run --' consumes the dash-dash
test_begin "'make run --' consumes the separator"
TMPDIR_SEP=$(mktemp -d)
TMP_DIRS+=("$TMPDIR_SEP")
PROJ_SEP="$TMPDIR_SEP/proj"
./c-init.sh --no-git "$PROJ_SEP" > /dev/null
cat <<EOF > "$PROJ_SEP/src/main.c"
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--") == 0) printf("FOUND_SEP\n");
        printf("ARG:%s\n", argv[i]);
    }
    return 0;
}
EOF
run make -C "$PROJ_SEP" run -- foo -v
assert_code 0
assert_contains "$LAST_OUT" "ARG:foo"
assert_contains "$LAST_OUT" "ARG:-v"
# Ensure "--" itself was NOT passed to the program
if [[ "$LAST_OUT" == *"FOUND_SEP"* ]]; then
    fail "dash-dash was not consumed by Makefile"
fi
test_ok

# 12) 'make run-release' with arguments
test_begin "'make run-release' passes arguments"
TMPDIR_REL=$(mktemp -d)
TMP_DIRS+=("$TMPDIR_REL")
PROJ_REL="$TMPDIR_REL/proj"
./c-init.sh --no-git "$PROJ_REL" > /dev/null
cat <<EOF > "$PROJ_REL/src/main.c"
#include <stdio.h>
int main(int argc, char **argv) {
    for (int i = 1; i < argc; i++) printf("ARG:%s\n", argv[i]);
    return 0;
}
EOF
run make -C "$PROJ_REL" run-release rel_foo rel_bar
assert_code 0
assert_contains "$LAST_OUT" "ARG:rel_foo"
assert_contains "$LAST_OUT" "ARG:rel_bar"
assert_file "$PROJ_REL/target/release/proj"
test_ok

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi
