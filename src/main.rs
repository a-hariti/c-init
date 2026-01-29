use clap::{ArgAction, CommandFactory, Parser, Subcommand, ValueEnum};
use dialoguer::{Select, theme::ColorfulTheme};
use indoc::{formatdoc, indoc};
use std::collections::VecDeque;
use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const FLAGS_LOOSE_BASE: &str = indoc!(
    r#"
    -std=c2x
    -Iinclude
    -Wall
    -Wextra
    "#
);
const FLAGS_STRICT_COMMON: &str = indoc!(
    r#"
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
    "#
);
const FLAGS_STRICTEST_COMMON: &str = indoc!(
    r#"
    -Wundef
    -Wformat=2
    -Wfloat-equal
    -Wswitch-default
    -Wdouble-promotion
    "#
);
const FLAGS_CLANG_SYSTEM_INCLUDES: &str = indoc!(
    r#"
    -isystem/opt/homebrew/include
    -isystem/usr/local/include
    "#
);
const FLAGS_GCC_STRICT_EXTRA: &str = indoc!(
    r#"
    -Wlogical-op
    -Wjump-misses-init
    "#
);
const FLAGS_GCC_STRICTEST_EXTRA: &str = indoc!(
    r#"
    -Wstrict-overflow=2
    -Wduplicated-cond
    -Wduplicated-branches
    -Wrestrict
    -Wnull-dereference
    -Wjump-misses-init
    "#
);
const FLAGS_CLANG_STRICTEST_EXTRA: &str = "-Wstrict-overflow=5";
const FLAGS_TEST_INCLUDE: &str = indoc!(
    r#"
    -I../include
    -I.
    -isystem
    ./test-deps
    "#
);

#[derive(Clone, Copy, Debug, ValueEnum)]
enum Compiler {
    Clang,
    Gcc,
}

#[derive(Clone, Copy, Debug, ValueEnum)]
enum Strictness {
    Loose,
    Strict,
    Strictest,
}

#[derive(Clone, Copy, Debug, ValueEnum)]
enum ColorWhen {
    Auto,
    Always,
    Never,
}

#[derive(Debug, Parser)]
#[command(name = "c-init", version, disable_help_subcommand = true)]
struct Cli {
    /// Help information
    #[command(subcommand)]
    command: Option<Commands>,

    /// Project name (defaults to directory name)
    #[arg(long)]
    name: Option<String>,

    /// Choose compiler
    #[arg(long, value_enum)]
    cc: Option<Compiler>,

    /// strictness: loose | strict | strictest
    #[arg(short = 's', long, value_enum)]
    strictness: Option<Strictness>,

    /// linter strictness: loose | strict | strictest
    #[arg(long, value_enum)]
    linter_strictness: Option<Strictness>,

    /// Color: auto | always | never
    #[arg(long, value_enum, default_value_t = ColorWhen::Auto)]
    color: ColorWhen,

    /// Allow non-empty directory
    #[arg(short = 'f', long, action = ArgAction::SetTrue)]
    force: bool,

    /// Skip git init and .gitignore
    #[arg(long, action = ArgAction::SetTrue)]
    no_git: bool,

    /// Skip initial git commit
    #[arg(long, action = ArgAction::SetTrue)]
    no_commit: bool,

    /// Skip generating src/main.c
    #[arg(long, action = ArgAction::SetTrue)]
    no_hello: bool,

    /// Skip generating tests and vendoring acutest
    #[arg(long, action = ArgAction::SetTrue)]
    no_tests: bool,

    /// Run interactive wizard
    #[arg(short = 'i', long, action = ArgAction::SetTrue)]
    interactive: bool,

    /// Project path
    path: Option<String>,
}

#[derive(Debug, Subcommand)]
enum Commands {
    /// Show help
    Help,
}

struct InputProvider {
    tty: bool,
    lines: VecDeque<String>,
}

impl InputProvider {
    fn new(interactive: bool) -> io::Result<Self> {
        let tty = interactive && atty::is(atty::Stream::Stdin);
        let mut lines = VecDeque::new();
        if interactive && !tty {
            let mut input = String::new();
            io::stdin().read_to_string(&mut input)?;
            lines.extend(input.lines().map(|s| s.to_string()));
        }
        Ok(Self { tty, lines })
    }

    fn read_line(&mut self, prompt: &str) -> io::Result<String> {
        print!("{}", prompt);
        io::stdout().flush()?;
        if self.tty {
            let mut input = String::new();
            io::stdin().read_line(&mut input)?;
            Ok(input.trim_end().to_string())
        } else {
            Ok(self.lines.pop_front().unwrap_or_default())
        }
    }
}

fn colorize(text: &str, code: &str, enabled: bool) -> String {
    if enabled {
        format!("\x1b[{}m{}\x1b[0m", code, text)
    } else {
        text.to_string()
    }
}

fn print_err(message: &str, color_enabled: bool) {
    let prefix = colorize("Error:", "31", color_enabled);
    eprintln!("{} {}", prefix, message);
}

fn warn(message: &str, color_enabled: bool) {
    let prefix = colorize("Warning:", "33", color_enabled);
    eprintln!("{} {}", prefix, message);
}

fn info(message: &str) {
    println!("{}", message);
}

fn green(text: &str, color_enabled: bool) -> String {
    colorize(text, "32", color_enabled)
}

fn muted(text: &str, color_enabled: bool) -> String {
    colorize(text, "90", color_enabled)
}

fn is_dir_nonempty(path: &Path) -> io::Result<bool> {
    if !path.exists() {
        return Ok(false);
    }
    if !path.is_dir() {
        return Ok(false);
    }
    let mut entries = fs::read_dir(path)?;
    Ok(entries.next().is_some())
}

fn select_menu(
    input: &mut InputProvider,
    prompt: &str,
    options: &[&str],
    default_idx: usize,
    color_enabled: bool,
) -> io::Result<usize> {
    let mut selected = default_idx;
    if !input.tty {
        let line = input.read_line("")?;
        if let Ok(idx) = line.trim().parse::<usize>() {
            if idx < options.len() {
                selected = idx;
            }
        }
        println!(
            "{}: {} (non-interactive)",
            prompt,
            green(options[selected], color_enabled)
        );
        return Ok(selected);
    }

    let theme = ColorfulTheme::default();
    let selection = Select::with_theme(&theme)
        .with_prompt(prompt)
        .items(options)
        .default(default_idx)
        .interact()
        .map_err(|err| io::Error::new(io::ErrorKind::Other, err))?;

    selected = selection;
    Ok(selected)
}

fn find_executable(name: &str) -> Option<PathBuf> {
    env::var_os("PATH").and_then(|paths| {
        env::split_paths(&paths)
            .map(|dir| dir.join(name))
            .find(|candidate| candidate.is_file())
    })
}

fn write_file(path: &Path, contents: &str) -> io::Result<()> {
    if let Some(parent) = path.parent() {
        if !parent.as_os_str().is_empty() {
            fs::create_dir_all(parent)?;
        }
    }
    fs::write(path, contents)
}

fn flags_concat(parts: &[&str]) -> String {
    parts
        .iter()
        .map(|part| part.trim())
        .filter(|trimmed| !trimmed.is_empty())
        .collect::<Vec<&str>>()
        .join("\n")
}

fn fetch_acutest(dest: &Path) -> io::Result<()> {
    const ACUTEST: &[u8] = include_bytes!("../assets/acutest.h");
    fs::write(dest, ACUTEST)
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    if matches!(cli.command, Some(Commands::Help)) {
        let mut cmd = Cli::command();
        let _ = cmd.print_help();
        println!();
        return ExitCode::SUCCESS;
    }

    let color_enabled = match cli.color {
        ColorWhen::Always => true,
        ColorWhen::Never => false,
        ColorWhen::Auto => atty::is(atty::Stream::Stdout),
    };

    let mut proj_name = cli.name;
    let mut proj_path = cli.path;
    let mut cc_choice = cli.cc;
    let mut strictness = cli.strictness;
    let mut linter_strictness = cli.linter_strictness;
    let mut force = cli.force;
    let mut no_git = cli.no_git;
    let no_commit = cli.no_commit;
    let no_hello = cli.no_hello;
    let mut no_tests = cli.no_tests;

    if cli.interactive {
        info("--- c-init Interactive Wizard ---");
        info("");

        let mut input = match InputProvider::new(true) {
            Ok(input) => input,
            Err(err) => {
                print_err(&format!("failed to read input: {}", err), color_enabled);
                return ExitCode::from(1);
            }
        };

        if proj_name.is_none() && proj_path.is_none() {
            let entry = match input.read_line("Project Name [.]: ") {
                Ok(entry) => entry,
                Err(err) => {
                    print_err(&format!("failed to read input: {}", err), color_enabled);
                    return ExitCode::from(1);
                }
            };
            if !entry.is_empty() && entry != "." {
                proj_path = Some(entry);
            }
        }

        let path_for_check = proj_path.clone().unwrap_or_else(|| ".".to_string());
        let path_for_check = PathBuf::from(path_for_check);
        if is_dir_nonempty(&path_for_check).unwrap_or(false) && !force {
            let res = match select_menu(
                &mut input,
                "Folder not empty. Overwrite?",
                &["No", "Yes"],
                0,
                color_enabled,
            ) {
                Ok(res) => res,
                Err(err) => {
                    print_err(&format!("failed to read input: {}", err), color_enabled);
                    return ExitCode::from(1);
                }
            };
            if res == 1 {
                force = true;
            } else {
                info("Exiting...");
                return ExitCode::from(1);
            }
        }

        if cc_choice.is_none() {
            let res = match select_menu(&mut input, "Compiler", &["clang", "gcc"], 0, color_enabled)
            {
                Ok(res) => res,
                Err(err) => {
                    print_err(&format!("failed to read input: {}", err), color_enabled);
                    return ExitCode::from(1);
                }
            };
            cc_choice = Some(if res == 1 {
                Compiler::Gcc
            } else {
                Compiler::Clang
            });
        }

        if strictness.is_none() {
            let res = match select_menu(
                &mut input,
                "Compiler Strictness",
                &["loose", "strict", "strictest"],
                1,
                color_enabled,
            ) {
                Ok(res) => res,
                Err(err) => {
                    print_err(&format!("failed to read input: {}", err), color_enabled);
                    return ExitCode::from(1);
                }
            };
            strictness = Some(match res {
                0 => Strictness::Loose,
                1 => Strictness::Strict,
                _ => Strictness::Strictest,
            });
        }

        if linter_strictness.is_none() {
            let res = match select_menu(
                &mut input,
                "Linter Strictness",
                &["(same as strictness)", "loose", "strict", "strictest"],
                0,
                color_enabled,
            ) {
                Ok(res) => res,
                Err(err) => {
                    print_err(&format!("failed to read input: {}", err), color_enabled);
                    return ExitCode::from(1);
                }
            };
            linter_strictness = match res {
                1 => Some(Strictness::Loose),
                2 => Some(Strictness::Strict),
                3 => Some(Strictness::Strictest),
                _ => None,
            };
        }

        let provided_no_git = env::args().any(|arg| arg == "--no-git");
        if !provided_no_git {
            let res = match select_menu(
                &mut input,
                "Run git init?",
                &["No", "Yes"],
                1,
                color_enabled,
            ) {
                Ok(res) => res,
                Err(err) => {
                    print_err(&format!("failed to read input: {}", err), color_enabled);
                    return ExitCode::from(1);
                }
            };
            no_git = res == 0;
        }

        let provided_no_tests = env::args().any(|arg| arg == "--no-tests");
        if !provided_no_tests {
            let res = match select_menu(
                &mut input,
                "Generate tests?",
                &["No", "Yes"],
                1,
                color_enabled,
            ) {
                Ok(res) => res,
                Err(err) => {
                    print_err(&format!("failed to read input: {}", err), color_enabled);
                    return ExitCode::from(1);
                }
            };
            no_tests = res == 0;
        }

        info("");
    }

    let cc_choice = cc_choice.unwrap_or(Compiler::Clang);
    let strictness = strictness.unwrap_or(Strictness::Strict);
    let linter_strictness = linter_strictness.unwrap_or(strictness);

    let mut proj_path = proj_path.unwrap_or_else(|| ".".to_string());
    if proj_path.is_empty() {
        proj_path = ".".to_string();
    }

    let path = PathBuf::from(&proj_path);
    if path != Path::new(".") {
        if let Err(err) = fs::create_dir_all(&path) {
            print_err(
                &format!("failed to create {}: {}", proj_path, err),
                color_enabled,
            );
            return ExitCode::from(1);
        }
    }

    if proj_name.is_none() {
        if path == Path::new(".") {
            if let Ok(current) = env::current_dir() {
                if let Some(name) = current.file_name().and_then(|s| s.to_str()) {
                    proj_name = Some(name.to_string());
                }
            }
        } else if let Some(name) = path.file_name().and_then(|s| s.to_str()) {
            proj_name = Some(name.to_string());
        }
    }

    let proj_name = proj_name.unwrap_or_else(|| "project".to_string());
    let proj_name_lower = proj_name.to_ascii_lowercase().replace(' ', "_");

    if is_dir_nonempty(&path).unwrap_or(false) && !force {
        print_err(
            &format!(
                "The folder {} is not empty (use --force to proceed)",
                proj_path
            ),
            color_enabled,
        );
        return ExitCode::from(1);
    }

    if let Err(err) = env::set_current_dir(&path) {
        print_err(
            &format!("failed to enter {}: {}", proj_path, err),
            color_enabled,
        );
        return ExitCode::from(1);
    }

    if let Err(err) = fs::create_dir_all("src") {
        print_err(&format!("failed to create src: {}", err), color_enabled);
        return ExitCode::from(1);
    }
    if let Err(err) = fs::create_dir_all("include") {
        print_err(&format!("failed to create include: {}", err), color_enabled);
        return ExitCode::from(1);
    }
    if let Err(err) = fs::create_dir_all("target") {
        print_err(&format!("failed to create target: {}", err), color_enabled);
        return ExitCode::from(1);
    }

    let mut actual_cc = match cc_choice {
        Compiler::Clang => "clang".to_string(),
        Compiler::Gcc => "gcc".to_string(),
    };

    if matches!(cc_choice, Compiler::Gcc) && cfg!(target_os = "macos") {
        for candidate in ["gcc-15", "gcc-14", "gcc-13"] {
            if find_executable(candidate).is_some() {
                actual_cc = candidate.to_string();
                break;
            }
        }
    }

    if !no_hello {
        let main_c = formatdoc!(
            r#"
            #include <stdio.h>

            int main(void) {{
              printf("Hello from %s!\n", "{proj_name}");
              return 0;
            }}
            "#,
            proj_name = proj_name
        );
        if let Err(err) = write_file(Path::new("src/main.c"), &main_c) {
            print_err(
                &format!("failed to write src/main.c: {}", err),
                color_enabled,
            );
            return ExitCode::from(1);
        }
    }

    if !no_tests {
        if let Err(err) = fs::create_dir_all("tests/test-deps") {
            print_err(
                &format!("failed to create tests/test-deps: {}", err),
                color_enabled,
            );
            return ExitCode::from(1);
        }
        if let Err(err) = fetch_acutest(Path::new("tests/test-deps/acutest.h")) {
            print_err(&format!("failed to write acutest: {}", err), color_enabled);
            return ExitCode::from(1);
        }
        const TEST_BASIC: &[u8] = include_bytes!("../assets/test_basic.c");
        if let Err(err) = fs::write(Path::new("tests/test_basic.c"), TEST_BASIC) {
            print_err(
                &format!("failed to write tests/test_basic.c: {}", err),
                color_enabled,
            );
            return ExitCode::from(1);
        }
    }

    let makefile_template = include_str!("../assets/Makefile");
    let phony = if !no_tests {
        "all run release run-release test sanitize fmt lint clean"
    } else {
        "all run release run-release sanitize fmt lint clean"
    };
    let mut makefile = makefile_template
        .replace("{CC}", &actual_cc)
        .replace("{NAME}", &proj_name_lower)
        .replace("{PHONY}", phony);
    if no_tests {
        if let (Some(start), Some(end)) = (
            makefile.find("# TEST_SECTION_BEGIN"),
            makefile.find("# TEST_SECTION_END"),
        ) {
            let end = end + "# TEST_SECTION_END".len();
            makefile.replace_range(
                start..end,
                "sanitize:\n\t@$(MAKE) SANITIZE=1 MODE=debug all\n",
            );
        }
    } else {
        makefile = makefile
            .replace("# TEST_SECTION_BEGIN\n", "")
            .replace("\n# TEST_SECTION_END", "");
    }
    if let Err(err) = write_file(Path::new("Makefile"), &makefile) {
        print_err(&format!("failed to write Makefile: {}", err), color_enabled);
        return ExitCode::from(1);
    }

    let (flags_loose, flags_strict, flags_strictest) = match cc_choice {
        Compiler::Clang => {
            let flags_loose = flags_concat(&[FLAGS_LOOSE_BASE, FLAGS_CLANG_SYSTEM_INCLUDES]);
            let flags_strict = flags_concat(&[&flags_loose, FLAGS_STRICT_COMMON]);
            let flags_strictest = flags_concat(&[
                &flags_strict,
                FLAGS_STRICTEST_COMMON,
                FLAGS_CLANG_STRICTEST_EXTRA,
            ]);
            (flags_loose, flags_strict, flags_strictest)
        }
        Compiler::Gcc => {
            let flags_loose = flags_concat(&[FLAGS_LOOSE_BASE]);
            let flags_strict =
                flags_concat(&[&flags_loose, FLAGS_STRICT_COMMON, FLAGS_GCC_STRICT_EXTRA]);
            let flags_strictest = flags_concat(&[
                &flags_strict,
                FLAGS_STRICTEST_COMMON,
                FLAGS_GCC_STRICTEST_EXTRA,
            ]);
            (flags_loose, flags_strict, flags_strictest)
        }
    };

    let selected_flags = match strictness {
        Strictness::Loose => flags_loose,
        Strictness::Strict => flags_strict,
        Strictness::Strictest => flags_strictest,
    };
    if let Err(err) = write_file(Path::new("compile_flags.txt"), &selected_flags) {
        print_err(
            &format!("failed to write compile_flags.txt: {}", err),
            color_enabled,
        );
        return ExitCode::from(1);
    }

    if !no_tests {
        let test_flags = selected_flags.replace(
            "-Iinclude",
            // clangd resolves the include directory from within ./tests
            // isystem ./test-deps avoids generating linting warnings for testing library code
            FLAGS_TEST_INCLUDE.trim(),
        );
        if let Err(err) = write_file(Path::new("tests/compile_flags.txt"), &test_flags) {
            print_err(
                &format!("failed to write tests/compile_flags.txt: {}", err),
                color_enabled,
            );
            return ExitCode::from(1);
        }
    }

    let clang_tidy: &[u8] = match linter_strictness {
        Strictness::Loose => include_bytes!("../assets/clang-tidy-loose.yaml"),
        Strictness::Strict => include_bytes!("../assets/clang-tidy-strict.yaml"),
        Strictness::Strictest => include_bytes!("../assets/clang-tidy-strictest.yaml"),
    };
    if let Err(err) = fs::write(Path::new(".clang-tidy"), clang_tidy) {
        print_err(
            &format!("failed to write .clang-tidy: {}", err),
            color_enabled,
        );
        return ExitCode::from(1);
    }

    let readme_template = include_str!("../assets/README.md");
    let readme = readme_template.replace("{PROJECT_NAME}", &proj_name);
    if let Err(err) = write_file(Path::new("README.md"), &readme) {
        print_err(
            &format!("failed to write README.md: {}", err),
            color_enabled,
        );
        return ExitCode::from(1);
    }

    if !no_git && !Path::new(".git").exists() {
        if Command::new("git")
            .args(["init", "-q"])
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            if let Err(err) = write_file(Path::new(".gitignore"), "target/\n") {
                print_err(
                    &format!("failed to write .gitignore: {}", err),
                    color_enabled,
                );
                return ExitCode::from(1);
            }
            if !no_commit {
                let _ = Command::new("git").args(["add", "-A"]).status();
                let _ = Command::new("git")
                    .args(["commit", "-m", "init"])
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .status();
            }
        }
    }

    info(&format!(
        "{} project '{}' at {} (using {})",
        green("Created", color_enabled),
        proj_name,
        proj_path,
        actual_cc
    ));
    info("");
    info("Next steps:");
    info(&format!(
        "  make         {}",
        muted("# debug build", color_enabled)
    ));
    info(&format!(
        "  make run     {}",
        muted("# build+run", color_enabled)
    ));
    info(&format!(
        "  make watch   {}",
        muted("# run in watch mode", color_enabled)
    ));
    if !no_tests {
        info(&format!(
            "  make test    {}",
            muted("# build and run tests", color_enabled)
        ));
    }
    info(&format!(
        "  make release {}",
        muted("# release build", color_enabled)
    ));
    info("\nHappy Hacking!");

    if cfg!(target_os = "macos") && actual_cc.starts_with("gcc") {
        warn(
            &muted(
                "Sanitizers may fail with GCC on macOS (ASan runtime missing). Prefer clang for 'make sanitize'.",
                color_enabled,
            ),
            color_enabled,
        );
    }

    ExitCode::SUCCESS
}
