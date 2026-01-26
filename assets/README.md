# {PROJECT_NAME}

## Build & Run

```sh
make           # build debug
make run       # build and run
make run foo   # build and run with arguments
make run -- -v # use -- to pass flags starting with -
make release   # build release
make test      # build and run tests
make sanitize  # build and run with address/UB sanitizers
```

Sanitizers add significant overhead and may require a recent clang/gcc toolchain.

## Format & Lint

```sh
make fmt     # format with clang-format
make lint    # lint with clang-tidy
```

## Project Structure

```
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
```
