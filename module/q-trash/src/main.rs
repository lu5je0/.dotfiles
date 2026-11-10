#[cfg(not(any(target_os = "linux", target_os = "macos")))]
compile_error!("q-trash supports Linux (including WSL) and macOS");
mod backend;
mod freedesktop;
#[cfg(any(target_os = "macos", test))]
mod macos;
mod rm;
mod util;
#[cfg(target_os = "linux")]
mod windows;

use std::{
    collections::BTreeMap,
    env,
    ffi::OsString,
    fs,
    io::{self, IsTerminal, Write},
    os::unix::ffi::{OsStrExt, OsStringExt},
    path::{Path, PathBuf},
};
use util::Result;
#[derive(Clone)]
pub struct Entry {
    original: PathBuf,
    date: String,
    order: i128,
    trash: PathBuf,
    info: Option<PathBuf>,
    file: PathBuf,
}
const HELP: &str = "Usage: q-trash [--trash-dir DIR] COMMAND [OPTIONS]\nManage trash (list / restore / empty / size / rm).\n\nCommands:\n  list, ls [PATH]     list trashed files, optionally filtered by original path\n  restore [PATH]      restore newest exact match or select interactively\n  empty               permanently delete trashed files\n  size                show trash disk usage\n  rm [OPTION] FILE... move files to trash (rm-compatible)\n\nOptions:\n  --trash-dir DIR     operate on a specific freedesktop trash directory\n  --current-disk      restrict list/restore/empty/size to the current volume\n  --help              show help\n  --version           show version\n\nRestore: --all --overwrite --dest PATH\nEmpty:   -f, --force --days N\nRun 'q-trash rm --help' for rm options.";
#[derive(Default)]
struct Options {
    trash: Option<PathBuf>,
    path: Option<PathBuf>,
    current_disk: bool,
    all: bool,
    overwrite: bool,
    dest: Option<PathBuf>,
    force: bool,
    days: Option<i64>,
}
fn color(code: &str, text: impl AsRef<str>, err: bool) -> String {
    let enabled = env::var_os("NO_COLOR").is_none()
        && env::var("TERM").as_deref() != Ok("dumb")
        && if err {
            io::stderr().is_terminal()
        } else {
            io::stdout().is_terminal()
        };
    if enabled {
        format!("\x1b[{code}m{}\x1b[0m", text.as_ref())
    } else {
        text.as_ref().to_owned()
    }
}
fn row(t: &Entry, err: bool) -> String {
    format!("{}  {}", color("2", &t.date, err), t.original.display())
}
fn next_value(argv: &[OsString], i: &mut usize, flag: &str) -> Result<OsString> {
    *i += 1;
    argv.get(*i)
        .cloned()
        .filter(|s| !s.to_string_lossy().starts_with("--"))
        .ok_or_else(|| format!("{flag} requires an argument"))
}
fn run() -> Result<i32> {
    let argv: Vec<OsString> = env::args_os().skip(1).collect();
    let mut opts = Options::default();
    let mut command = None;
    let mut end = false;
    let mut i = 0;
    while i < argv.len() {
        let value = argv[i].to_string_lossy();
        let flag = value.split('=').next().unwrap();
        if command.as_deref() == Some("rm") {
            return rm::run(&argv[i..]);
        }
        match value.as_ref() {
            "--help" | "-h" if !end => {
                println!("{HELP}");
                return Ok(0);
            }
            "--version" if !end => {
                println!("q-trash {}", env!("CARGO_PKG_VERSION"));
                return Ok(0);
            }
            "--" if !end => end = true,
            _ if !end && matches!(flag, "--trash-dir" | "--dest" | "--days") => {
                let argument = if let Some(pos) = argv[i].as_bytes().iter().position(|b| *b == b'=')
                {
                    OsString::from_vec(argv[i].as_bytes()[pos + 1..].to_vec())
                } else {
                    next_value(&argv, &mut i, flag)?
                };
                match flag {
                    "--trash-dir" => opts.trash = Some(argument.into()),
                    "--dest" if command.as_deref() == Some("restore") => {
                        opts.dest = Some(argument.into())
                    }
                    "--days" if command.as_deref() == Some("empty") => {
                        opts.days = Some(
                            argument
                                .to_str()
                                .and_then(|s| s.parse().ok())
                                .ok_or("--days requires an integer")?,
                        )
                    }
                    _ => return Err(format!("unrecognized argument: {flag}")),
                }
            }
            "--current-disk" if !end && command.is_some() => opts.current_disk = true,
            "--all" if !end && command.as_deref() == Some("restore") => opts.all = true,
            "--overwrite" if !end && command.as_deref() == Some("restore") => opts.overwrite = true,
            "--force" | "-f" if !end && command.as_deref() == Some("empty") => opts.force = true,
            _ if !end && value.starts_with('-') => {
                return Err(format!("unrecognized argument: {value}"));
            }
            _ if command.is_none() => {
                if !matches!(
                    value.as_ref(),
                    "list" | "ls" | "restore" | "empty" | "size" | "rm"
                ) {
                    return Err(format!(
                        "unknown command '{value}'\nTry 'q-trash --help' for more information."
                    ));
                }
                command = Some(value.into_owned());
            }
            _ if matches!(command.as_deref(), Some("list" | "ls" | "restore"))
                && opts.path.is_none() =>
            {
                opts.path = Some(util::absolute(Path::new(&argv[i])).map_err(|e| e.to_string())?)
            }
            _ => return Err(format!("unrecognized argument: {value}")),
        }
        i += 1;
    }
    match command.as_deref() {
        None => {
            println!("{HELP}");
            Ok(0)
        }
        Some("rm") => rm::run(&[]),
        Some(cmd) => manage(cmd, opts),
    }
}
fn matches_path(entry: &Entry, path: &Path) -> bool {
    entry.original == path || entry.original.starts_with(path)
}
fn manage(command: &str, opts: Options) -> Result<i32> {
    let mut items = backend::scan(opts.trash.as_deref(), opts.current_disk)?;
    match command {
        "list" | "ls" => {
            if let Some(path) = &opts.path {
                items.retain(|t| matches_path(t, path));
            }
            if items.is_empty() {
                eprintln!("{}", color("2", "No trashed files.", true));
            }
            for t in items {
                println!("{}", row(&t, false));
            }
            Ok(0)
        }
        "restore" => restore(items, opts),
        "empty" => {
            if let Some(days) = opts.days {
                let now = util::now();
                items.retain(|t| {
                    util::parse_date(&t.date)
                        .is_some_and(|stamp| (now - stamp).div_euclid(86400) >= days)
                });
            }
            if items.is_empty() {
                println!("Trash is already empty.");
                return Ok(0);
            }
            let n = items.len();
            let suffix = if n == 1 { "" } else { "s" };
            if !opts.force {
                let age = opts
                    .days
                    .map(|d| format!(" (older than {d} days)"))
                    .unwrap_or_default();
                if !util::prompt(&format!("Permanently delete {n} item{suffix}?{age} [y/N] ")) {
                    println!("Cancelled.");
                    return Ok(0);
                }
            }
            let mut deleted = 0;
            let mut ok = true;
            for t in items {
                if util::exists(&t.file) {
                    if let Err(e) = util::remove(&t.file, false) {
                        eprintln!("q-trash: cannot delete '{}': {e}", t.file.display());
                        ok = false;
                        continue;
                    }
                }
                if let Some(info) = t.info {
                    if let Err(e) = fs::remove_file(info) {
                        eprintln!("q-trash: cannot remove trash metadata: {e}");
                        ok = false;
                        continue;
                    }
                }
                deleted += 1;
            }
            println!(
                "Deleted {deleted} item{}.",
                if deleted == 1 { "" } else { "s" }
            );
            Ok(if ok { 0 } else { 1 })
        }
        "size" => {
            if items.is_empty() {
                println!("All trash directories are empty.");
                return Ok(0);
            }
            let mut sized: Vec<_> = items
                .iter()
                .filter_map(|t| {
                    fs::symlink_metadata(&t.file).ok().map(|m| {
                        (
                            if m.is_dir() {
                                dir_size(&t.file)
                            } else {
                                m.len()
                            },
                            t,
                        )
                    })
                })
                .collect();
            sized.sort_by_key(|(size, _)| std::cmp::Reverse(*size));
            let total: u64 = sized.iter().map(|(s, _)| s).sum();
            for (size, t) in &sized {
                println!("{:>10}  {}", human_size(*size), row(t, false));
            }
            let n = sized.len();
            println!(
                "{:>10}  Total ({n} item{})",
                human_size(total),
                if n == 1 { "" } else { "s" }
            );
            Ok(0)
        }
        _ => unreachable!(),
    }
}
fn restore(mut items: Vec<Entry>, opts: Options) -> Result<i32> {
    let exact = opts
        .path
        .as_ref()
        .and_then(|p| items.iter().rfind(|t| t.original == *p))
        .cloned();
    if !opts.all && exact.is_some() {
        items = vec![exact.unwrap()];
    } else {
        if let Some(path) = &opts.path {
            items.retain(|t| matches_path(t, path));
        }
        if items.is_empty() {
            return Err(opts
                .path
                .map(|p| format!("No files trashed from '{}'", p.display()))
                .unwrap_or_else(|| "No trashed files.".into()));
        }
        if opts.all {
            // Keep the newest version of each original path, retaining scan order.
            let mut latest = BTreeMap::new();
            for (idx, t) in items.iter().enumerate() {
                latest.insert(t.original.clone(), idx);
            }
            items = items
                .iter()
                .enumerate()
                .filter(|(idx, t)| latest.get(&t.original) == Some(idx))
                .map(|(_, t)| t.clone())
                .collect();
        } else {
            for (idx, t) in items.iter().enumerate() {
                eprintln!("  {idx:3}  {}", row(t, true));
            }
            eprint!("What to restore [0..{}, all, quit]: ", items.len() - 1);
            let _ = io::stderr().flush();
            let line = util::input().map_err(|e| e.to_string())?;
            let line = line.trim();
            if matches!(line, "" | "quit" | "q") {
                return Ok(0);
            }
            if line != "all" {
                let mut selected = Vec::new();
                for token in line.split([',', ' ']).filter(|s| !s.is_empty()) {
                    let idx: usize = token.parse().map_err(|_| "invalid input")?;
                    selected.push(
                        items
                            .get(idx)
                            .ok_or_else(|| format!("index {idx} out of range"))?
                            .clone(),
                    );
                }
                items = selected;
            }
        }
    }
    let dest = opts
        .dest
        .map(|p| util::absolute(&p))
        .transpose()
        .map_err(|e| e.to_string())?;
    let mut directory = dest
        .as_ref()
        .is_some_and(|p| fs::symlink_metadata(p).is_ok_and(|m| m.is_dir()));
    if let Some(dest) = &dest {
        if items.len() > 1 && !directory {
            fs::create_dir_all(dest)
                .map_err(|e| format!("cannot create dest '{}': {e}", dest.display()))?;
            directory = true;
        }
    }
    let mut ok = true;
    for t in items {
        let target = dest
            .as_ref()
            .map(|d| {
                if directory {
                    d.join(
                        t.original
                            .file_name()
                            .unwrap_or(t.file.file_name().unwrap()),
                    )
                } else {
                    d.clone()
                }
            })
            .unwrap_or_else(|| t.original.clone());
        let result = restore_one(&t, &target, opts.overwrite);
        match result {
            Ok(()) => println!("Restored: {}", target.display()),
            Err(e) => {
                eprintln!("q-trash: {e}");
                ok = false;
            }
        }
    }
    Ok(if ok { 0 } else { 1 })
}
fn restore_one(t: &Entry, target: &Path, overwrite: bool) -> Result<()> {
    if !util::exists(&t.file) {
        return Err(format!("backup file missing: '{}'", t.file.display()));
    }
    if !target.is_absolute() {
        return Err(format!(
            "original path unknown for '{}'; use --dest",
            t.file.display()
        ));
    }
    let source_location = util::location(&t.file).map_err(|e| e.to_string())?;
    let target_location = util::location(target).map_err(|e| e.to_string())?;
    if source_location.starts_with(&target_location)
        || target_location.starts_with(&source_location)
    {
        return Err("restore destination overlaps the backup".into());
    }
    if util::exists(target) {
        if !overwrite {
            return Err(format!(
                "'{}' already exists (use --overwrite)",
                target.display()
            ));
        }
        util::remove(target, false).map_err(|e| e.to_string())?;
    }
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    }
    util::rename_exclusive(&t.file, target)
        .map_err(|e| format!("cannot restore '{}': {e}", target.display()))?;
    if let Some(info) = &t.info {
        fs::remove_file(info).map_err(|e| {
            format!(
                "restored file but cannot remove metadata '{}': {e}",
                info.display()
            )
        })?;
    }
    Ok(())
}
fn dir_size(path: &Path) -> u64 {
    fs::read_dir(path)
        .map(|entries| {
            entries
                .flatten()
                .map(|e| {
                    fs::symlink_metadata(e.path())
                        .map(|m| {
                            if m.is_dir() {
                                dir_size(&e.path())
                            } else {
                                m.len()
                            }
                        })
                        .unwrap_or(0)
                })
                .sum()
        })
        .unwrap_or(0)
}
fn human_size(n: u64) -> String {
    let mut size = n as f64;
    for unit in ["B", "KB", "MB", "GB", "TB", "PB"] {
        if size < 1024.0 || unit == "PB" {
            return if unit == "B" {
                format!("{n} B")
            } else {
                format!("{size:.1} {unit}")
            };
        }
        size /= 1024.0;
    }
    unreachable!()
}
fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(error) => {
            eprintln!("q-trash: {error}");
            std::process::exit(1);
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::ffi::OsStrExt;
    #[test]
    fn paths_roundtrip_bytes() {
        let bytes = b"/a b/%#\xff/\xe4\xb8\xad";
        let path = Path::new(std::ffi::OsStr::from_bytes(bytes));
        assert_eq!(
            util::decode(util::encode(path).as_bytes()).unwrap(),
            path.as_os_str()
        );
        assert!(util::decode(b"%00").is_none());
        assert!(util::decode(b"%xx").is_none());
    }
    #[test]
    fn mount_escapes() {
        assert_eq!(
            freedesktop::decode_mount(b"/mnt/a\\040b\\134c"),
            b"/mnt/a b\\c"
        );
    }
}
