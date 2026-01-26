CC      := clang
RM      := rm -rf
NAME    := example
SRC_DIR := src
INC_DIR := include

CFLAGS_BASE  := @compile_flags.txt

CFLAGS_DEBUG   := -O0 -g
CFLAGS_RELEASE := -O3 -DNDEBUG
CFLAGS_SANITIZE := -fsanitize=address,undefined -fno-omit-frame-pointer -O1 -g
LDFLAGS_SANITIZE := -fsanitize=address,undefined

MODE ?= debug
SANITIZE ?= 0
ifeq ($(MODE),release)
  BUILD_DIR := target/release
  CFLAGS_MODE := $(CFLAGS_RELEASE)
else
  BUILD_DIR := target/debug
  CFLAGS_MODE := $(CFLAGS_DEBUG)
endif

ifeq ($(SANITIZE),1)
  CFLAGS_EXTRA := $(CFLAGS_SANITIZE)
  LDFLAGS_EXTRA := $(LDFLAGS_SANITIZE)
else
  CFLAGS_EXTRA :=
  LDFLAGS_EXTRA :=
endif

CFLAGS := $(CFLAGS_BASE) $(CFLAGS_MODE) $(CFLAGS_EXTRA)
LDFLAGS := $(LDFLAGS_EXTRA)
OBJ_DIR := $(BUILD_DIR)
TARGET = $(BUILD_DIR)/$(NAME)

SOURCES := $(wildcard $(SRC_DIR)/*.c)
OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o)

# Some cursed make magic to enable make run [args]
# If the first argument is "run" or "run-release"...
ifeq ($(firstword $(MAKECMDGOALS)),$(filter $(firstword $(MAKECMDGOALS)),run run-release))
  # Extract all goals after the first one
  ALL_GOALS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  # If the first argument is "--", skip it for the program args but keep it for targets
  ifeq ($(firstword $(ALL_GOALS)),--)
    RUN_ARGS := $(wordlist 2,$(words $(ALL_GOALS)),$(ALL_GOALS))
  else
    RUN_ARGS := $(ALL_GOALS)
  endif
  # Define all captured goals as do-nothing targets
  $(eval $(ALL_GOALS):;@:)
endif

all: $(TARGET)

# Build and run
run: $(TARGET)
	@./$(TARGET) $(RUN_ARGS)

release:
	@$(MAKE) MODE=release

run-release:
	@$(MAKE) MODE=release RUN_ARGS="$(RUN_ARGS)" run

# Link the executable
$(TARGET): $(OBJECTS)
	@mkdir -p $(OBJ_DIR)
	$(CC) $(OBJECTS) -o $(TARGET) $(LDFLAGS)

# Compile source files to object files
$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	@mkdir -p $(OBJ_DIR)
	$(CC) $(CFLAGS) -c $< -o $@
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
.PHONY: all run release run-release test sanitize fmt lint clean
