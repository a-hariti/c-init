#!/usr/bin/env bash

set -euo pipefail

show_help() {
  cat <<'EOF'
Usage: c-init.sh [options] [path]

Options:
  --name NAME                  Project name (defaults to directory name)
  --cc clang|gcc               Choose compiler (default: clang)
  -s, --strictness LEVEL       loose | strict (default) | strictest
  --linter-strictness LEVEL    loose | strict | strictest (overrides -s for lint only)
  --color WHEN                 Color: auto (default) | always | never
  --force                      Allow non-empty directory
  --no-git                     Skip git init and .gitignore
  --no-commit                  Skip initial git commit
  --no-hello                   Skip generating src/main.c
  --no-tests                   Skip generating tests and vendoring acutest
  -i, --interactive            Run interactive wizard
  -h, --help                   Show this help
EOF
}

COLOR_WHEN="auto"
COLOR_ENABLED=1
CC_CHOICE=""
STRICTNESS=""
LINTER_STRICTNESS=""
FORCE=-1
NO_GIT=-1
NO_COMMIT=-1
NO_HELLO=-1
NO_TESTS=-1
PROJ_NAME=""
PROJ_PATH=""
INTERACTIVE=0

err() {
  if [ "${COLOR_ENABLED:-0}" -eq 1 ]; then
    printf "\033[31mError:\033[0m %s\n" "$*" >&2
  else
    printf "Error: %s\n" "$*" >&2
  fi
}

warn() {
  if [ "${COLOR_ENABLED:-0}" -eq 1 ]; then
    printf "\033[33mWarning:\033[0m %s\n" "$*" >&2
  else
    printf "Warning: %s\n" "$*" >&2
  fi
}

info() {
  printf "%s\n" "$*"
}

green() {
  if [ "${COLOR_ENABLED:-0}" -eq 1 ]; then
    printf "\033[32m%s\033[0m" "$1"
  else
    printf "%s" "$1"
  fi
}

muted() {
  if [ "${COLOR_ENABLED:-0}" -eq 1 ]; then
    printf "\033[90m%s\033[0m" "$1"
  else
    printf "%s" "$1"
  fi
}

select_menu() {
  local prompt="$1"
  shift
  local options=("$@")
  local count=${#options[@]}
  local current=0
  local default_idx=${DEFAULT_MENU_IDX:-0}
  current=$default_idx

  if [ ! -t 0 ]; then
    # Try to read once if there is input
    if read -r input; then
      if [[ "$input" =~ ^[0-9]+$ ]] && [ "$input" -lt "$count" ]; then
        current=$input
      fi
    fi
    printf "%s: \033[32m%s\033[0m (non-interactive)\n" "$prompt" "${options[$current]}"
    return "$current"
  fi

  # Hide cursor, save screen
  if [ -t 0 ] && [ -n "${TERM:-}" ]; then tput civis; fi

  draw_menu() {
    printf "%s:\n" "$prompt"
    for i in "${!options[@]}"; do
      if [ "$i" -eq "$current" ]; then
        printf "\033[7m> %s\033[0m\n" "${options[$i]}"
      else
        printf "  %s\n" "${options[$i]}"
      fi
    done
  }

  clear_menu() {
    for ((i=0; i<=count; i++)); do
      printf "\033[A\033[2K"
    done
    printf "\r"
  }

  draw_menu

  while true; do
    read -rsn3 key
    case "$key" in
      $'\033[A') # Up
        ((current > 0)) && current=$((current - 1))
        ;;
      $'\033[B') # Down
        ((current < count - 1)) && current=$((current + 1))
        ;;
      "") # Enter
        break
        ;;
    esac
    clear_menu
    draw_menu
  done

  clear_menu
  if [ -t 0 ] && [ -n "${TERM:-}" ]; then tput cnorm; fi
  printf "%s: \033[32m%s\033[0m\n" "$prompt" "${options[$current]}"
  return "$current"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      [ $# -ge 2 ] || { err "--name requires a value"; exit 1; }
      PROJ_NAME="$2"
      shift 2
      ;;
    --cc)
      [ $# -ge 2 ] || { err "--cc requires a value"; exit 1; }
      CC_CHOICE="$2"
      shift 2
      ;;
    -s|--strictness)
      [ $# -ge 2 ] || { err "--strictness requires a value"; exit 1; }
      STRICTNESS="$2"
      shift 2
      ;;
    --linter-strictness)
      [ $# -ge 2 ] || { err "--linter-strictness requires a value"; exit 1; }
      LINTER_STRICTNESS="$2"
      shift 2
      ;;
    --color)
      [ $# -ge 2 ] || { err "--color requires a value"; exit 1; }
      COLOR_WHEN="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    --no-git)
      NO_GIT=1
      shift
      ;;
    --no-commit)
      NO_COMMIT=1
      shift
      ;;
    --no-hello)
      NO_HELLO=1
      shift
      ;;
    --no-tests)
      NO_TESTS=1
      shift
      ;;
    -i|--interactive)
      INTERACTIVE=1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      err "Unknown option: $1"
      printf "\n" >&2
      show_help >&2
      exit 1
      ;;
    *)
      if [ -z "${PROJ_PATH}" ]; then
        PROJ_PATH="$1"
      else
        err "Unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ "$INTERACTIVE" -eq 1 ]; then
  info "--- c-init Interactive Wizard ---"
  info ""
  res=0

  if [ -z "$PROJ_NAME" ] && [ -z "$PROJ_PATH" ]; then
    if [ -t 0 ]; then
      printf "Project Name [.]: "
      read -r input || input=""
      if [ -n "$input" ] && [ "$input" != "." ]; then
        PROJ_PATH="$input"
      fi
    else
      # If not a TTY, try reading from stdin once for the name
      read -r input || input=""
      if [ -n "$input" ] && [ "$input" != "." ]; then
        PROJ_PATH="$input"
      fi
    fi
  fi

  [ -z "$PROJ_PATH" ] && PROJ_PATH="."

  if [ -d "$PROJ_PATH" ] && [ "$(ls -A "$PROJ_PATH")" ] && [ "$FORCE" -eq -1 ]; then
    res=0
    DEFAULT_MENU_IDX=0 select_menu "Folder not empty. Overwrite?" "No" "Yes" || res=$?
    if [ "$res" -eq 1 ]; then
      FORCE=1
    else
      info "Exiting..."
      exit 1
    fi
  fi

  if [ -z "$CC_CHOICE" ]; then
    DEFAULT_MENU_IDX=0 select_menu "Compiler" "clang" "gcc" || res=$?
    if [ "$res" -eq 1 ]; then CC_CHOICE="gcc"; else CC_CHOICE="clang"; fi
  fi

  if [ -z "$STRICTNESS" ]; then
    DEFAULT_MENU_IDX=1 select_menu "Compiler Strictness" "loose" "strict" "strictest" || res=$?
    case "$res" in
      0) STRICTNESS="loose" ;;
      1) STRICTNESS="strict" ;;
      2) STRICTNESS="strictest" ;;
    esac
  fi

  if [ -z "$LINTER_STRICTNESS" ]; then
    DEFAULT_MENU_IDX=0 select_menu "Linter Strictness" "(same as strictness)" "loose" "strict" "strictest" || res=$?
    case "$res" in
      0) LINTER_STRICTNESS="" ;;
      1) LINTER_STRICTNESS="loose" ;;
      2) LINTER_STRICTNESS="strict" ;;
      3) LINTER_STRICTNESS="strictest" ;;
    esac
  fi

  if [ "$NO_GIT" -eq -1 ]; then
    DEFAULT_MENU_IDX=1 select_menu "Run git init?" "No" "Yes" || res=$?
    if [ "$res" -eq 1 ]; then NO_GIT=0; else NO_GIT=1; fi
  fi

  if [ "$NO_TESTS" -eq -1 ]; then
    DEFAULT_MENU_IDX=1 select_menu "Generate tests?" "No" "Yes" || res=$?
    if [ "$res" -eq 1 ]; then NO_TESTS=0; else NO_TESTS=1; fi
  fi

  info ""
fi

# Apply defaults for non-interactive or non-provided flags
[ -z "$CC_CHOICE" ] && CC_CHOICE="clang"

# On macOS, 'gcc' is often an alias for 'clang'. Try to find a real GCC.
ACTUAL_CC="$CC_CHOICE"
if [ "$CC_CHOICE" = "gcc" ] && [[ "$OSTYPE" == "darwin"* ]]; then
  if command -v gcc-15 >/dev/null 2>&1; then
    ACTUAL_CC="gcc-15"
  elif command -v gcc-14 >/dev/null 2>&1; then
    ACTUAL_CC="gcc-14"
  elif command -v gcc-13 >/dev/null 2>&1; then
    ACTUAL_CC="gcc-13"
  fi
fi

[ -z "$STRICTNESS" ] && STRICTNESS="strict"
[ "$FORCE" -eq -1 ] && FORCE=0
[ "$NO_GIT" -eq -1 ] && NO_GIT=0
[ "$NO_COMMIT" -eq -1 ] && NO_COMMIT=0
[ "$NO_HELLO" -eq -1 ] && NO_HELLO=0
[ "$NO_TESTS" -eq -1 ] && NO_TESTS=0

case "$COLOR_WHEN" in
  auto) COLOR_ENABLED=1 ;;
  always) COLOR_ENABLED=1 ;;
  never) COLOR_ENABLED=0 ;;
  *)
    err "--color must be auto, always, or never"
    exit 1
    ;;
esac

if [ "$COLOR_WHEN" = "auto" ] && [ ! -t 1 ]; then
  COLOR_ENABLED=0
fi

# `help` should behave like --help unless specifically passed via --name
if [ "$PROJ_PATH" = "help" ] && [ -z "$PROJ_NAME" ]; then
  show_help
  exit 0
fi

case "$CC_CHOICE" in
  clang|gcc) ;;
  *)
    err "--cc must be clang or gcc"
    exit 1
    ;;
esac

case "$STRICTNESS" in
  loose|strict|strictest) ;;
  *)
    err "--strictness must be loose, strict, or strictest"
    exit 1
    ;;
esac

if [ -n "$LINTER_STRICTNESS" ]; then
  case "$LINTER_STRICTNESS" in
    loose|strict|strictest) ;;
    *)
      err "--linter-strictness must be loose, strict, or strictest"
      exit 1
      ;;
  esac
else
  LINTER_STRICTNESS="$STRICTNESS"
fi

# 1. Determine Project Name
# If no argument or "." is provided, use the current directory name
if [ -z "$PROJ_PATH" ]; then
  PROJ_PATH="."
fi

if [ "$PROJ_PATH" = "." ]; then
  PROJ_PATH="."
  if [ -z "$PROJ_NAME" ]; then
    PROJ_NAME=$(basename "$PWD")
  fi
else
  mkdir -p "$PROJ_PATH"
  if [ -z "$PROJ_NAME" ]; then
    PROJ_NAME=$(basename "$PROJ_PATH")
  fi
fi

PROJ_NAME_LOWER=$(printf "%s" "$PROJ_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

# make sure it is empty
if [[ $(ls -A "$PROJ_PATH") ]] && [ "$FORCE" -ne 1 ]; then
    err "The folder $PROJ_PATH is not empty (use --force to proceed)"
    exit 1
fi

cd "$PROJ_PATH" || exit

# Create Directory Structure
mkdir -p src include target

fetch_acutest() {
  local dest="$1"
  local acutest_url="https://raw.githubusercontent.com/mity/acutest/refs/heads/master/include/acutest.h"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$acutest_url" -o "$dest"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$dest" "$acutest_url"
    return
  fi

  err "curl or wget is required to download acutest (set --no-tests to skip)"
  exit 1
}

# Entry point
if [ "$NO_HELLO" -ne 1 ]; then
cat <<EOF > src/main.c
#include <stdio.h>

int main(void) {
  printf("Hello from %s!\n", "$PROJ_NAME");
  return 0;
}
EOF
fi

if [ "$NO_TESTS" -ne 1 ]; then
  mkdir -p tests/test-deps
  fetch_acutest "tests/test-deps/acutest.h"
  cat <<'EOF' > tests/test_basic.c
#include <stdlib.h>

#define ACUTEST_IMPLEMENTATION
#include "acutest.h"

static void test_tutorial(void) {
  void *mem;

  mem = malloc(10);
  TEST_CHECK(mem != NULL);

  void *mem2 = realloc(mem, 20);
  TEST_CHECK(mem2 != NULL);
  mem = mem2;

  free(mem);
}

static void test_addition(void) {
  int a = 1;
  int b = 2;
  TEST_CHECK(a + b == 3);
}

TEST_LIST = {
    {"tutorial", test_tutorial},
    {"addition", test_addition},
    {NULL, NULL},
};
EOF
fi

cat <<EOF > Makefile
CC      := $ACTUAL_CC
RM      := rm -rf
NAME    := $PROJ_NAME_LOWER
SRC_DIR := src
INC_DIR := include

CFLAGS_BASE  := @compile_flags.txt

CFLAGS_DEBUG   := -O0 -g
CFLAGS_RELEASE := -O3 -DNDEBUG
CFLAGS_SANITIZE := -fsanitize=address,undefined -fno-omit-frame-pointer -O1 -g
LDFLAGS_SANITIZE := -fsanitize=address,undefined

MODE ?= debug
SANITIZE ?= 0
ifeq (\$(MODE),release)
  BUILD_DIR := target/release
  CFLAGS_MODE := \$(CFLAGS_RELEASE)
else
  BUILD_DIR := target/debug
  CFLAGS_MODE := \$(CFLAGS_DEBUG)
endif

ifeq (\$(SANITIZE),1)
  CFLAGS_EXTRA := \$(CFLAGS_SANITIZE)
  LDFLAGS_EXTRA := \$(LDFLAGS_SANITIZE)
else
  CFLAGS_EXTRA :=
  LDFLAGS_EXTRA :=
endif

CFLAGS := \$(CFLAGS_BASE) \$(CFLAGS_MODE) \$(CFLAGS_EXTRA)
LDFLAGS := \$(LDFLAGS_EXTRA)
OBJ_DIR := \$(BUILD_DIR)
TARGET = \$(BUILD_DIR)/\$(NAME)

SOURCES := \$(wildcard \$(SRC_DIR)/*.c)
OBJECTS := \$(SOURCES:\$(SRC_DIR)/%.c=\$(OBJ_DIR)/%.o)

# Some cursed make magic to enable make run [args]
# If the first argument is "run" or "run-release"...
ifeq (\$(firstword \$(MAKECMDGOALS)),\$(filter \$(firstword \$(MAKECMDGOALS)),run run-release))
  # Extract all goals after the first one
  ALL_GOALS := \$(wordlist 2,\$(words \$(MAKECMDGOALS)),\$(MAKECMDGOALS))
  # If the first argument is "--", skip it for the program args but keep it for targets
  ifeq (\$(firstword \$(ALL_GOALS)),--)
    RUN_ARGS := \$(wordlist 2,\$(words \$(ALL_GOALS)),\$(ALL_GOALS))
  else
    RUN_ARGS := \$(ALL_GOALS)
  endif
  # Define all captured goals as do-nothing targets
  \$(eval \$(ALL_GOALS):;@:)
endif

all: \$(TARGET)

# Build and run
run: \$(TARGET)
	@./\$(TARGET) \$(RUN_ARGS)

release:
	@\$(MAKE) MODE=release

run-release:
	@\$(MAKE) MODE=release RUN_ARGS="\$(RUN_ARGS)" run

# Link the executable
\$(TARGET): \$(OBJECTS)
	@mkdir -p \$(OBJ_DIR)
	\$(CC) \$(OBJECTS) -o \$(TARGET) \$(LDFLAGS)

# Compile source files to object files
\$(OBJ_DIR)/%.o: \$(SRC_DIR)/%.c
	@mkdir -p \$(OBJ_DIR)
	\$(CC) \$(CFLAGS) -c $< -o \$@
EOF

if [ "$NO_TESTS" -ne 1 ]; then
cat <<'EOF' >> Makefile
TEST_DIR := tests
TEST_BUILD_DIR := $(BUILD_DIR)/tests
TEST_TARGET := $(TEST_BUILD_DIR)/$(NAME)_tests
TEST_CFLAGS_BASE := @compile_flags.txt
TEST_CFLAGS := $(TEST_CFLAGS_BASE) $(CFLAGS_MODE)

TEST_SOURCES := $(wildcard $(TEST_DIR)/*.c)
TEST_OBJECTS := $(TEST_SOURCES:$(TEST_DIR)/%.c=$(TEST_BUILD_DIR)/%.o)

ifneq ($(strip $(TEST_SOURCES)),)
test: $(TEST_TARGET)
	@./$(TEST_TARGET)

$(TEST_TARGET): $(TEST_OBJECTS)
	@mkdir -p $(TEST_BUILD_DIR)
	$(CC) $(TEST_OBJECTS) -o $(TEST_TARGET) $(LDFLAGS)

$(TEST_BUILD_DIR)/%.o: $(TEST_DIR)/%.c
	@mkdir -p $(TEST_BUILD_DIR)
	@cd $(TEST_DIR) && \
		$(CC) $(TEST_CFLAGS) -c $(notdir $<) -o ../$@
else
test:
	@echo "No tests found in $(TEST_DIR)/ (add *.c)."
endif
sanitize:
	@$(MAKE) SANITIZE=1 MODE=debug test
EOF
fi

if [ "$NO_TESTS" -eq 1 ]; then
cat <<'EOF' >> Makefile
sanitize:
	@$(MAKE) SANITIZE=1 MODE=debug all
EOF
fi

cat <<'EOF' >> Makefile
fmt:
	@command -v clang-format >/dev/null && \
		clang-format -i --style=file --fallback-style=LLVM $(SOURCES) $(wildcard $(INC_DIR)/*.h) || \
		echo "clang-format not found, skipping"

lint:
	@command -v clang-tidy >/dev/null && \
		clang-tidy --quiet $(SOURCES) -- $(CFLAGS) || \
		echo "clang-tidy not found, skipping"

clean:
	$(RM) target
EOF

if [ "$NO_TESTS" -ne 1 ]; then
  echo ".PHONY: all run release run-release test sanitize fmt lint clean" >> Makefile
else
  echo ".PHONY: all run release run-release sanitize fmt lint clean" >> Makefile
fi
# Create compile_flags.txt for IDEs and consumption by make
FLAGS_LOOSE=(
  -std=c11
  -Iinclude
  -Wall
  -Wextra
)

# Common strict flags for both compilers
FLAGS_STRICT_COMMON=(
  -Werror
  -Wpedantic
  -Wcast-align
  -Wpointer-arith
  -Wmissing-prototypes
  -Wstrict-prototypes
  -Wsign-conversion
  -Wswitch-enum
  -Wconversion
  -Wcast-qual
  -Wshadow
)

# Common strictest flags for both compilers
FLAGS_STRICTEST_COMMON=(
  -Wundef
  -Wformat=2
  -Wfloat-equal
  -Wswitch-default
  -Wdouble-promotion
)

if [ "$CC_CHOICE" = "clang" ]; then
  FLAGS_LOOSE+=(
    -isystem/opt/homebrew/include
    -isystem/usr/local/include
  )
  FLAGS_STRICT=(
    "${FLAGS_LOOSE[@]}"
    "${FLAGS_STRICT_COMMON[@]}"
  )
  FLAGS_STRICTEST=(
    "${FLAGS_STRICT[@]}"
    "${FLAGS_STRICTEST_COMMON[@]}"
    -Wstrict-overflow=5
  )
else
  # GCC
  FLAGS_STRICT=(
    "${FLAGS_LOOSE[@]}"
    "${FLAGS_STRICT_COMMON[@]}"
    -Wlogical-op
    -Wjump-misses-init
  )
  FLAGS_STRICTEST=(
    "${FLAGS_STRICT[@]}"
    "${FLAGS_STRICTEST_COMMON[@]}"
    -Wstrict-overflow=2
    -Wduplicated-cond
    -Wduplicated-branches
    -Wrestrict
    -Wnull-dereference
    -Wjump-misses-init
  )
fi

case "$STRICTNESS" in
  loose)
    printf "%s\n" "${FLAGS_LOOSE[@]}" > compile_flags.txt
    ;;
  strict)
    printf "%s\n" "${FLAGS_STRICT[@]}" > compile_flags.txt
    ;;
  strictest)
    printf "%s\n" "${FLAGS_STRICTEST[@]}" > compile_flags.txt
    ;;
esac

if [ "$NO_TESTS" -ne 1 ]; then
  awk '
    $0 == "-Iinclude" { print "-I../include"; print "-I."; print "-isystem"; print "./test-deps"; next }
    { print }
  ' compile_flags.txt > tests/compile_flags.txt
fi

case "$LINTER_STRICTNESS" in
  loose)
    cat <<EOF > .clang-tidy
# Minimal: diagnostics + analyzer
Checks: 'clang-diagnostic-*,clang-analyzer-*'

WarningsAsErrors: '*'
HeaderFilterRegex: 'include/.*'
EOF
    ;;
  strict)
    cat <<EOF > .clang-tidy
Checks: 'clang-diagnostic-*,clang-analyzer-*,bugprone-*,performance-*,-clang-analyzer-security.insecureAPI.DeprecatedOrUnsafeBufferHandling,-bugprone-easily-swappable-parameters,-performance-padding'

WarningsAsErrors: '*'
HeaderFilterRegex: 'include/.*'

CheckOptions:
  - key:             bugprone-signed-char-misuse.CharTypingCertCheck
    value:           'true'
EOF
    ;;
  strictest)
    cat <<EOF > .clang-tidy
Checks: 'clang-diagnostic-*,clang-analyzer-*,bugprone-*,performance-*,portability-*,readability-*,modernize-*,misc-*'

WarningsAsErrors: '*'
HeaderFilterRegex: 'include/.*'

CheckOptions:
  - key:             readability-identifier-naming.FunctionCase
    value:           lower_case
  - key:             readability-identifier-naming.VariableCase
    value:           lower_case
  - key:             readability-identifier-naming.ParameterCase
    value:           lower_case
  - key:             bugprone-signed-char-misuse.CharTypingCertCheck
    value:           'true'
EOF
    ;;
esac

cat <<EOF > README.md
# $PROJ_NAME

## Build & Run

\`\`\`sh
make           # build debug
make run       # build and run
make run foo   # build and run with arguments
make run -- -v # use -- to pass flags starting with -
make release   # build release
make test      # build and run tests
make sanitize  # build and run with address/UB sanitizers
\`\`\`

Sanitizers add significant overhead and may require a recent clang/gcc toolchain.

## Format & Lint

\`\`\`sh
make fmt     # format with clang-format
make lint    # lint with clang-tidy
\`\`\`

## Project Structure

\`\`\`
.
├── include/                 # public headers
├── src/                     # sources
├── tests/                   # tests + vendored acutest
│   └── compile_flags.txt    # test-specific compile flags for clangd
├── target/                  # build outputs
│   ├── debug/               # debug artifacts
│   └── release/             # release artifacts
├── Makefile
└── README.md
\`\`\`
EOF

# 8. Initialize Git
if [ "$NO_GIT" -ne 1 ] && [ ! -d ".git" ]; then
    git init -q
    printf "target/\n" > .gitignore
    if [ "$NO_COMMIT" -ne 1 ]; then
      git add -A
      git commit -m "init" >/dev/null
    fi
fi

info "$(green Created) project '$PROJ_NAME' at $PROJ_PATH (using $ACTUAL_CC)"
info ""
info "Next steps:"
info "  make         $(muted '# debug build')"
info "  make run     $(muted '# build+run')"
info "  make release $(muted '# release build')"
if [ "$NO_TESTS" -ne 1 ]; then
  info "  make test    $(muted '# build and run tests')"
fi
if [[ "$OSTYPE" == "darwin"* ]] && [[ "$ACTUAL_CC" == gcc* ]]; then
  warn "$(muted "Sanitizers may fail with GCC on macOS (ASan runtime missing). Prefer clang for 'make sanitize'.")"
fi
