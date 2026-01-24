#!/bin/bash

# 1. Determine Project Name
# If no argument or "." is provided, use the current directory name
PROJ_NAME=${1:-.}
if [ "$PROJ_NAME" = "." ]; then
    PROJ_NAME=$(basename "$PWD")
    PROJ_PATH="."
else
    PROJ_PATH=$PROJ_NAME
    mkdir -p "$PROJ_PATH"
fi

# make sure it is empty
if [[ $(ls -A "$PROJ_PATH") ]]; then
    echo "Error: The folder $PROJ_PATH is not empty" >&2
    exit 1
fi

cd "$PROJ_PATH" || exit

# 2. Create Directory Structure
mkdir -p src include build

# 3. Entry point
cat <<EOF > src/main.c
#include <stdio.h>

int main(void) {
  printf("Hello from %s!\n", "$PROJ_NAME");
  return 0;
}
EOF

# 4. Create a strict Makefile (using Clang)
cat <<EOF > Makefile
CC      := clang
RM      := rm -rf
# Naming the binary based on project name
TARGET  := build/\$(shell basename "\$(PWD)" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
SRC_DIR := src
OBJ_DIR := build
INC_DIR := include

# Extra strict flags
CFLAGS  := -std=c11 -I\$(INC_DIR) \\
           -Wall -Wextra -Werror -Wpedantic \\
           -Wshadow -Wpointer-arith -Wcast-align \\
           -Wstrict-prototypes -Wmissing-prototypes \\
           -Wconversion -Wformat=2 -O2

SOURCES := \$(wildcard \$(SRC_DIR)/*.c)
OBJECTS := \$(SOURCES:\$(SRC_DIR)/%.c=\$(OBJ_DIR)/%.o)

all: \$(TARGET)

# Build and run
run: \$(TARGET)
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
	clang-format -i --style=file --fallback-style=LLVM \$(SOURCES) \$(wildcard \$(INC_DIR)/*.h)

lint:
	@clang-tidy \$(SOURCES) -- \$(CFLAGS)

clean:
	\$(RM) \$(OBJ_DIR)

.PHONY: all run fmt lint clean
EOF

# 5. Create a strict .clang-tidy configuration
cat <<EOF > .clang-tidy
# Enable all checks by default, then disable specific noisy/unwanted ones
Checks: 'clang-diagnostic-*,clang-analyzer-*,bugprone-*,performance-*,portability-*,readability-*,modernize-*,misc-*'

# Specific configuration details
WarningsAsErrors: '*'
HeaderFilterRegex: 'include/.*'

# Check Options
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

# 6. Create basic README.md
echo "# $PROJ_NAME" > README.md

# 7. Initialize Git
if [ ! -d ".git" ]; then
    git init -q
    echo "build/" > .gitignore
fi

echo "Created project '$PROJ_NAME' at $PROJ_PATH"
