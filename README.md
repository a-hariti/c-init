# C init

Bring the simplicity of Rust's Cargo to C.

[![asciicast](https://asciinema.org/a/JgMRkyLA8PJZHPeE.svg)](https://asciinema.org/a/JgMRkyLA8PJZHPeE)

## Usage

```sh
c-init [options] [path]
```

From source:

```sh
cargo run -- [options] [path]
```

Add to `~/.cargo/bin`:

```sh
cargo install --path .
```

Options:

- `--name NAME` Project name (defaults to directory name)
- `--cc clang|gcc` Choose compiler (default: clang)
- `-s, --strictness LEVEL` loose | strict (default) | strictest
- `--linter-strictness LEVEL` loose | strict | strictest (overrides `-s` for lint only)
- `--no-tests` Skip generating tests and vendoring acutest
- `--color WHEN` auto (default) | always | never
- `--force` Allow non-empty directory
- `--no-git` Skip git init and .gitignore
- `--no-commit` Skip initial git commit
- `--no-hello` Skip generating `src/main.c`
- `-i, --interactive` Run interactive wizard
- `-h, --help` Show help

Example:

```sh
c-init my_app
```

## Example project

An `./example` project is included in this repo with the default settings so you can see the generated output.

## Expected Output

```text
Created project 'my_app' at my_app

Next steps:
  make          # debug build
  make run      # build+run
  make release  # release build
  make test     # build and run tests
  make sanitize # build and run with address/UB sanitizers
```

## What you get

- Strict compiler flags by default (with loose/strict/strictest levels).
- clang-tidy config wired to your chosen strictness.
- Tests scaffolded with [Acutest](https://github.com/mity/acutest), plus a `make test` target.
- Clean project ready for LSP.
- Sanitizer target for quick memory/UB checks.

The generated project structure:

```text
my_app/
├── include/               # public headers
├── src/                   # sources
│   └── main.c             # entry point
├── target/                # build output
├── tests/
│   ├── test_basic.c       # starter tests
│   ├── test-deps/         # vendored test deps
│   │   └── acutest.h      # acutest single-header lib
│   └── compile_flags.txt  # clangd flags for tests
├── .clang-tidy            # lint config
├── compile_flags.txt      # clangd/flags for app sources
├── Makefile               # build + run targets
└── README.md              # project guide
```

## Philosophy

- Simplicity : Use tools you're familiar with.
- Sensible defaults : Everything you need to actually start coding.
- Stay out of the way : Not yet another config file in your root directory, You own your code base.

## Licence

MIT
