# C init

Bring the simplicity of Rust's Cargo to C.

## Usage

```sh
./c-init.sh [options] [path]
```

Or run via curl:

```sh
curl -fsSL https://raw.githubusercontent.com/a-hariti/c-init/master/c-init.sh | bash -s -- my_app # [options]
```

Options:

- `--name NAME`                  Project name (defaults to directory name)
- `--cc clang|gcc`               Choose compiler (default: clang)
- `-s, --strictness LEVEL`       loose | strict (default) | strictest
- `--linter-strictness LEVEL`    loose | strict | strictest (overrides `-s` for lint only)
- `--no-tests`                   Skip generating tests and vendoring acutest
- `--color WHEN`                 auto (default) | always | never
- `--force`                      Allow non-empty directory
- `--no-git`                     Skip git init and .gitignore
- `--no-hello`                   Skip generating `src/main.c`
- `-i, --interactive`            Run interactive wizard
- `-h, --help`                   Show help

Example:

```sh
./c-init.sh my_app
```

## Expected Output

```text
Created project 'my_app' at my_app

Next steps:
  make         # debug build
  make run     # build+run
  make release # release build
  make test    # build and run tests
```

The generated project structure:

```text
my_app/
├── include/
├── src/
│   └── main.c
├── target/
├── .clang-tidy
├── compile_flags.txt
├── Makefile
└── README.md
```

## Philosophy

- Simplicity : Use tools you're familiar with.
- Sensible defaults : Everything you need to actually start coding.
- Stay out of the way : Not yet another config file in your root directory, You own your code base.

## Licence

MIT
