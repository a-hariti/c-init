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
  --no-hello                   Skip generating src/main.c
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
NO_HELLO=-1
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
    --no-hello)
      NO_HELLO=1
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
    DEFAULT_MENU_IDX=0 select_menu "Folder not empty. Overwrite?" "No" "Yes"
    res=$?
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
[ "$NO_HELLO" -eq -1 ] && NO_HELLO=0

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
CC      := $ACTUAL_CC
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

# Some cursed make magic to enable `make run [args]`
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
	@\$(MAKE) MODE=release
	@./\$(TARGET) \$(RUN_ARGS)

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
\`\`\`

## Format & Lint

\`\`\`sh
make fmt     # format with clang-format
make lint    # lint with clang-tidy
\`\`\`

## Project Structure

\`\`\`
.
├── include/           # public headers
├── src/               # sources
├── target/            # build outputs
│   ├── debug/         # debug artifacts
│   └── release/       # release artifacts
├── Makefile
└── README.md
\`\`\`
EOF

# 8. Initialize Git
if [ "$NO_GIT" -ne 1 ] && [ ! -d ".git" ]; then
    git init -q
    printf "target/\n" > .gitignore
fi

info "$(green Created) project '$PROJ_NAME' at $PROJ_PATH (using $ACTUAL_CC)"
info ""
info "Next steps:"
info "  make         $(muted '# debug build')"
info "  make run     $(muted '# build+run')"
info "  make release $(muted '# release build')"
