use crate::{
    backend,
    util::{self, Result},
};
use std::{ffi::OsString, fs, os::unix::ffi::OsStrExt, path::PathBuf};

#[derive(Default, PartialEq)]
enum Interactive {
    #[default]
    Never,
    Once,
    Always,
}
#[derive(Default)]
struct Args {
    force: bool,
    interactive: Interactive,
    recursive: bool,
    dir: bool,
    verbose: bool,
    no_preserve_root: bool,
    one_fs: bool,
    purge: bool,
    files: Vec<PathBuf>,
}
const HELP: &str = "Usage: q-trash rm [OPTION]... [FILE]...\nMove FILEs to trash (rm-compatible).\n\n  -f, --force           ignore nonexistent files, never prompt\n  -i                    prompt before every removal\n  -I                    prompt once for >3 operands or recursive removal\n      --interactive[=WHEN]  never, once, always\n  -r, -R, --recursive   remove directories recursively\n  -d, --dir             remove empty directories\n  -v, --verbose         explain what is being done\n      --preserve-root   do not remove / (default)\n      --no-preserve-root  disable root protection\n      --one-file-system  skip directories on other filesystems when purging\n      --purge           delete permanently instead of trashing\n      --help            show help\n\nCross-volume moves are refused on Linux; use --purge to delete permanently.";
fn parse(argv: &[OsString]) -> Result<Option<Args>> {
    let mut a = Args::default();
    let mut end = false;
    for arg in argv {
        let bytes = arg.as_bytes();
        if end || !bytes.starts_with(b"-") || bytes == b"-" {
            a.files.push(arg.into());
            continue;
        }
        if bytes == b"--" {
            end = true;
            continue;
        }
        let s = arg.to_str().ok_or("invalid option encoding")?;
        if let Some(long) = s.strip_prefix("--") {
            let (name, value) = long
                .split_once('=')
                .map_or((long, None), |(k, v)| (k, Some(v)));
            if value.is_some() && name != "interactive" {
                return Err(format!("option '--{name}' doesn't allow an argument"));
            }
            match name {
                "help" => {
                    println!("{HELP}");
                    return Ok(None);
                }
                "force" => {
                    a.force = true;
                    a.interactive = Interactive::Never;
                }
                "recursive" => a.recursive = true,
                "dir" => a.dir = true,
                "verbose" => a.verbose = true,
                "preserve-root" => a.no_preserve_root = false,
                "no-preserve-root" => a.no_preserve_root = true,
                "one-file-system" => a.one_fs = true,
                "purge" => a.purge = true,
                "interactive" => match value.unwrap_or("always") {
                    "always" | "yes" => {
                        a.interactive = Interactive::Always;
                        a.force = false;
                    }
                    "once" => {
                        a.interactive = Interactive::Once;
                        a.force = false;
                    }
                    "never" | "no" | "none" => a.interactive = Interactive::Never,
                    v => return Err(format!("invalid argument '{v}' for '--interactive'")),
                },
                _ => return Err(format!("unrecognized option '--{name}'")),
            }
        } else {
            for ch in s[1..].chars() {
                match ch {
                    'f' => {
                        a.force = true;
                        a.interactive = Interactive::Never;
                    }
                    'i' => {
                        a.interactive = Interactive::Always;
                        a.force = false;
                    }
                    'I' => {
                        a.interactive = Interactive::Once;
                        a.force = false;
                    }
                    'r' | 'R' => a.recursive = true,
                    'd' => a.dir = true,
                    'v' => a.verbose = true,
                    _ => return Err(format!("invalid option -- '{ch}'")),
                }
            }
        }
    }
    Ok(Some(a))
}
pub fn run(argv: &[OsString]) -> Result<i32> {
    let Some(a) = parse(argv)? else {
        return Ok(0);
    };
    if a.files.is_empty() {
        return if a.force {
            Ok(0)
        } else {
            Err("rm: missing operand\nTry 'q-trash rm --help' for more information.".into())
        };
    }
    if a.interactive == Interactive::Once && (a.recursive || a.files.len() > 3) {
        let n = a.files.len();
        if !util::prompt(&format!(
            "q-trash: remove {n} argument{}{}? ",
            if n == 1 { "" } else { "s" },
            if a.recursive { " recursively" } else { "" }
        )) {
            return Ok(0);
        }
    }
    let mut ok = true;
    let mut accepted = Vec::new();
    for path in &a.files {
        let display = path.display();
        let raw = path.as_os_str().as_bytes();
        // Check the operand spelling before normalization; spaces are valid filename bytes.
        let tail = raw.trim_end_slashes();
        let last = tail.rsplit(|b| *b == b'/').next().unwrap_or_default();
        let validation = if raw.is_empty() {
            if a.force {
                continue;
            }
            Err(format!("cannot remove '': No such file or directory"))
        } else if last == b"." || last == b".." {
            Err(format!(
                "refusing to remove '.' or '..' directory: skipping '{display}'"
            ))
        } else if !a.no_preserve_root
            && util::absolute(path).is_ok_and(|p| p == std::path::Path::new("/"))
        {
            Err("it is dangerous to operate recursively on '/'\nq-trash: use --no-preserve-root to override this failsafe".into())
        } else {
            match fs::symlink_metadata(path) {
                Err(e) if e.kind() == std::io::ErrorKind::NotFound && a.force => continue,
                Err(e) => Err(format!(
                    "cannot remove '{display}': {}",
                    util::error_text(&e)
                )),
                Ok(meta) if meta.is_dir() && !(a.recursive || a.dir) => {
                    Err(format!("cannot remove '{display}': Is a directory"))
                }
                Ok(meta) if meta.is_dir() && a.dir && !a.recursive => match fs::read_dir(path) {
                    Ok(mut entries) => {
                        if entries.next().is_none() {
                            Ok(true)
                        } else {
                            Err(format!("cannot remove '{display}': Directory not empty"))
                        }
                    }
                    Err(e) => Err(format!("cannot remove '{display}': {e}")),
                },
                Ok(_) => Ok(true),
            }
        };
        if let Err(e) = validation {
            eprintln!("q-trash: {e}");
            ok = false;
            continue;
        }
        if a.interactive == Interactive::Always {
            let kind = if fs::symlink_metadata(path).is_ok_and(|m| m.is_dir()) {
                "directory"
            } else {
                "regular file"
            };
            if !util::prompt(&format!("q-trash: remove {kind} '{display}'? ")) {
                continue;
            }
        }
        accepted.push(path.clone());
    }
    if a.purge {
        for path in accepted {
            match util::remove(&path, a.one_fs) {
                Ok(()) => {
                    if a.verbose {
                        println!("removed '{}'", path.display());
                    }
                }
                Err(e) => {
                    eprintln!(
                        "q-trash: cannot remove '{}': {}",
                        path.display(),
                        util::error_text(&e)
                    );
                    ok = false;
                }
            }
        }
    } else {
        let errors = backend::trash(&accepted);
        if errors.is_empty() {
            if a.verbose {
                for path in accepted {
                    println!("removed '{}'", path.display());
                }
            }
        } else {
            for error in errors {
                eprintln!("q-trash: {error}");
            }
            ok = false;
        }
    }
    Ok(if ok { 0 } else { 1 })
}
trait TrimSlashes {
    fn trim_end_slashes(&self) -> &[u8];
}
impl TrimSlashes for [u8] {
    fn trim_end_slashes(&self) -> &[u8] {
        let mut end = self.len();
        while end > 0 && self[end - 1] == b'/' {
            end -= 1;
        }
        &self[..end]
    }
}
