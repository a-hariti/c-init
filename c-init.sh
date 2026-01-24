#!/bin/bash

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
  --no-hello                   Skip generating src/main.c
  -h, --help                   Show this help
EOF
}

COLOR_WHEN="auto"
CC_CHOICE="clang"
STRICTNESS="strict"
LINTER_STRICTNESS=""
FORCE=0
NO_GIT=0
NO_HELLO=0
PROJ_NAME=""
PROJ_PATH=""

err() {
  if [ "$COLOR_ENABLED" -eq 1 ]; then
    printf "\033[31mError:\033[0m %s\n" "$*" >&2
  else
    printf "Error: %s\n" "$*" >&2
  fi
}

info() {
  printf "%s\n" "$*"
}

green() {
  if [ "$COLOR_ENABLED" -eq 1 ]; then
    printf "\033[32m%s\033[0m" "$1"
  else
    printf "%s" "$1"
  fi
}

muted() {
  if [ "$COLOR_ENABLED" -eq 1 ]; then
    printf "\033[90m%s\033[0m" "$1"
  else
    printf "%s" "$1"
  fi
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
    --no-hello)
      NO_HELLO=1
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      err "Unknown option: $1"
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

cat <<EOF > Makefile
CC      ?= $CC_CHOICE
RM      := rm -rf
NAME    := $PROJ_NAME_LOWER
SRC_DIR := src
INC_DIR := include

CFLAGS_BASE  := \$(shell cat compile_flags.txt)

CFLAGS_DEBUG   := -O0 -g
CFLAGS_RELEASE := -O3 -DNDEBUG

MODE ?= debug
ifeq (\$(MODE),release)
  BUILD_DIR := target/release
  CFLAGS_MODE := \$(CFLAGS_RELEASE)
else
  BUILD_DIR := target/debug
  CFLAGS_MODE := \$(CFLAGS_DEBUG)
endif

CFLAGS := \$(CFLAGS_BASE) \$(CFLAGS_MODE)
OBJ_DIR := \$(BUILD_DIR)
TARGET = \$(BUILD_DIR)/\$(NAME)

SOURCES := \$(wildcard \$(SRC_DIR)/*.c)
OBJECTS := \$(SOURCES:\$(SRC_DIR)/%.c=\$(OBJ_DIR)/%.o)

all: \$(TARGET)

# Build and run
run: \$(TARGET)
	@./\$(TARGET)

release:
	@\$(MAKE) MODE=release

run-release:
	@\$(MAKE) MODE=release
	@./\$(TARGET)

# Link the executable
\$(TARGET): \$(OBJECTS)
	@mkdir -p \$(OBJ_DIR)
	\$(CC) \$(OBJECTS) -o \$(TARGET)

# Compile source files to object files
\$(OBJ_DIR)/%.o: \$(SRC_DIR)/%.c
	@mkdir -p \$(OBJ_DIR)
	\$(CC) \$(CFLAGS) -c $< -o \$@

fmt:
	@command -v clang-format >/dev/null && \\
		clang-format -i --style=file --fallback-style=LLVM \$(SOURCES) \$(wildcard \$(INC_DIR)/*.h) || \\
		echo "clang-format not found, skipping"

lint:
	@command -v clang-tidy >/dev/null && \\
		clang-tidy --quiet \$(SOURCES) -- \$(CFLAGS) || \\
		echo "clang-tidy not found, skipping"

clean:
	\$(RM) target

.PHONY: all run release run-release fmt lint clean
EOF

# Create compile_flags.txt for IDEs and consumption by make
FLAGS_LOOSE=(
  -std=c11
  -Iinclude
  -Wall
  -Wextra
)

FLAGS_STRICT=(
  "${FLAGS_LOOSE[@]}"
  -Werror
  -Wpedantic
  -Wshadow
  -Wpointer-arith
  -Wcast-align
  -Wstrict-prototypes
  -Wmissing-prototypes
  -Wconversion
  -Wformat=2
  -Wswitch-enum
  -Wcast-qual
)

FLAGS_STRICTEST=(
  "${FLAGS_STRICT[@]}"
  -Wstrict-overflow=5
  -Wundef
)

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
Checks: 'clang-diagnostic-*,clang-analyzer-*,bugprone-*,performance-*'

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
make run       # build debug and run
make release   # build release
\`\`\`

## Format & Lint

\`\`\`sh
make fmt     # format with clang-format
make lint    # lint with clang-tidy
\`\`\`

## Project Structure

\`\`\`
.
├── include/
├── src/
├── target/
│   ├── debug/
│   └── release/
├── Makefile
└── README.md
\`\`\`
EOF

# 8. Initialize Git
if [ "$NO_GIT" -ne 1 ] && [ ! -d ".git" ]; then
    git init -q
    printf "target/\n" > .gitignore
fi

info "$(green Created) project '$PROJ_NAME' at $PROJ_PATH"
info ""
info "Next steps:"
info "  make         $(muted '# debug build')"
info "  make run     $(muted '# build+run')"
info "  make release $(muted '# release build')"
