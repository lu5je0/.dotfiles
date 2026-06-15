use crate::backend;
use std::fs;
use std::io::Write;
use std::os::unix::fs::MetadataExt;

const PROG: &str = "q-trash";

pub struct RmArgs {
    pub force: bool,
    pub interactive: Interactive,
    pub recursive: bool,
    pub dir_only: bool,
    pub verbose: bool,
    pub preserve_root: bool,
    pub one_file_system: bool,
    pub purge: bool,
    pub files: Vec<String>,
}

#[derive(PartialEq)]
pub enum Interactive {
    Never,
    Once,
    Always,
}

impl Default for RmArgs {
    fn default() -> Self {
        Self {
            force: false,
            interactive: Interactive::Never,
            recursive: false,
            dir_only: false,
            verbose: false,
            preserve_root: true,
            one_file_system: false,
            purge: false,
            files: vec![],
        }
    }
}

pub fn parse_rm_args(argv: &[String]) -> RmArgs {
    let mut a = RmArgs::default();
    let mut end_of_opts = false;
    let mut i = 0;

    while i < argv.len() {
        let s = &argv[i];
        i += 1;

        if end_of_opts || s.is_empty() || !s.starts_with('-') || s == "-" {
            a.files.push(s.clone());
            continue;
        }
        if s == "--" {
            end_of_opts = true;
            continue;
        }
        if s.starts_with("--") {
            let rest = &s[2..];
            let (name, val) = match rest.find('=') {
                Some(pos) => (&rest[..pos], Some(&rest[pos + 1..])),
                None => (rest, None),
            };
            match name {
                "help" => {
                    print_rm_help();
                    std::process::exit(0);
                }
                "force" => { a.force = true; a.interactive = Interactive::Never; }
                "recursive" => a.recursive = true,
                "dir" => a.dir_only = true,
                "verbose" => a.verbose = true,
                "preserve-root" => a.preserve_root = true,
                "no-preserve-root" => a.preserve_root = false,
                "one-file-system" => a.one_file_system = true,
                "purge" => a.purge = true,
                "interactive" => {
                    match val {
                        None | Some("always") | Some("yes") => {
                            a.interactive = Interactive::Always;
                            a.force = false;
                        }
                        Some("once") => {
                            a.interactive = Interactive::Once;
                            a.force = false;
                        }
                        Some("never") | Some("no") | Some("none") => {
                            a.interactive = Interactive::Never;
                        }
                        Some(v) => die(&format!("invalid argument '{}' for '--interactive'", v)),
                    }
                }
                _ => die(&format!("unrecognized option '--{}'", name)),
            }
            continue;
        }
        for ch in s[1..].chars() {
            match ch {
                'f' => { a.force = true; a.interactive = Interactive::Never; }
                'i' => { a.interactive = Interactive::Always; a.force = false; }
                'I' => { a.interactive = Interactive::Once; a.force = false; }
                'r' | 'R' => a.recursive = true,
                'd' => a.dir_only = true,
                'v' => a.verbose = true,
                _ => die(&format!("invalid option -- '{}'", ch)),
            }
        }
    }
    a
}

fn die(msg: &str) {
    eprintln!("{}: {}", PROG, msg);
    std::process::exit(1);
}

fn prompt(msg: &str) -> bool {
    eprint!("{}: {}", PROG, msg);
    let _ = std::io::stderr().flush();
    let mut line = String::new();
    match std::io::stdin().read_line(&mut line) {
        Ok(0) | Err(_) => false,
        Ok(_) => line.trim().to_lowercase().starts_with('y'),
    }
}

fn is_dot_or_dotdot(path: &str) -> bool {
    let p = path.trim_end_matches('/');
    let base = p.rsplit('/').next().unwrap_or(p);
    base == "." || base == ".."
}

fn is_root_path(path: &str) -> bool {
    let trimmed = path.trim_end_matches('/');
    trimmed.is_empty() || trimmed == "/"
}

fn purge_one(path: &str, verbose: bool, one_fs: bool) -> Result<(), String> {
    let meta = fs::symlink_metadata(path).map_err(|e| e.to_string())?;

    if meta.is_symlink() || !meta.is_dir() {
        fs::remove_file(path).map_err(|e| e.to_string())?;
        if verbose {
            println!("removed '{}'", path);
        }
        return Ok(());
    }

    if one_fs {
        let top_dev = meta.dev();
        remove_dir_one_fs(path, top_dev, verbose)?;
    } else {
        fs::remove_dir_all(path).map_err(|e| e.to_string())?;
    }
    if verbose {
        println!("removed directory '{}'", path);
    }
    Ok(())
}

fn remove_dir_one_fs(path: &str, top_dev: u64, verbose: bool) -> Result<(), String> {
    let entries = fs::read_dir(path).map_err(|e| e.to_string())?;
    for entry in entries.flatten() {
        let p = entry.path();
        let m = match p.symlink_metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };
        if m.is_dir() && !m.is_symlink() {
            if m.dev() == top_dev {
                remove_dir_one_fs(p.to_str().unwrap_or(""), top_dev, verbose)?;
                let _ = fs::remove_dir(&p);
                if verbose {
                    println!("removed directory '{}'", p.display());
                }
            }
        } else {
            let _ = fs::remove_file(&p);
            if verbose {
                println!("removed '{}'", p.display());
            }
        }
    }
    fs::remove_dir(path).map_err(|e| e.to_string())
}

fn validate_one(path: &str, args: &RmArgs) -> (bool, bool) {
    if path.is_empty() {
        if args.force {
            return (true, false);
        }
        eprintln!("{}: cannot remove '': No such file or directory", PROG);
        return (false, false);
    }

    if is_dot_or_dotdot(path) {
        eprintln!(
            "{}: refusing to remove '.' or '..' directory: skipping '{}'",
            PROG, path
        );
        return (false, false);
    }

    if args.preserve_root && is_root_path(path) {
        eprintln!(
            "{}: it is dangerous to operate recursively on '/'\n{}: use --no-preserve-root to override this failsafe",
            PROG, PROG
        );
        return (false, false);
    }

    let meta = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            if args.force {
                return (true, false);
            }
            eprintln!("{}: cannot remove '{}': No such file or directory", PROG, path);
            return (false, false);
        }
        Err(e) => {
            eprintln!("{}: cannot stat '{}': {}", PROG, path, e);
            return (false, false);
        }
    };

    let is_dir = meta.is_dir();
    if is_dir && !(args.recursive || args.dir_only) {
        eprintln!("{}: cannot remove '{}': Is a directory", PROG, path);
        return (false, false);
    }
    if is_dir && args.dir_only && !args.recursive {
        match fs::read_dir(path) {
            Ok(mut entries) => {
                if entries.next().is_some() {
                    eprintln!("{}: cannot remove '{}': Directory not empty", PROG, path);
                    return (false, false);
                }
            }
            Err(e) => {
                eprintln!("{}: cannot remove '{}': {}", PROG, path, e);
                return (false, false);
            }
        }
    }

    if args.interactive == Interactive::Always {
        let kind = if is_dir { "directory" } else { "regular file" };
        if !prompt(&format!("remove {} '{}'? ", kind, path)) {
            return (true, false);
        }
    }

    (true, true)
}

fn print_rm_help() {
    println!(
        "Usage: {} rm [OPTION]... [FILE]...
Move FILEs to trash (rm-compatible).

  -f, --force           ignore nonexistent files and arguments, never prompt
  -i                    prompt before every removal
  -I                    prompt once before removing more than three files,
                          or when removing recursively
      --interactive[=WHEN]  prompt according to WHEN: never, once (-I), always (-i)
  -r, -R, --recursive   remove directories and their contents recursively
  -d, --dir             remove empty directories
  -v, --verbose         explain what is being done
      --preserve-root   do not remove '/' (default)
      --no-preserve-root  do not treat '/' specially
      --one-file-system  when recursive, skip directories on different filesystems
      --purge           bypass trash, delete permanently
      --help            display this help and exit",
        PROG
    );
}

pub fn run(argv: &[String]) -> i32 {
    let args = parse_rm_args(argv);

    if args.files.is_empty() {
        if args.force {
            return 0;
        }
        eprintln!(
            "{}: rm: missing operand\nTry '{} rm --help' for more information.",
            PROG, PROG
        );
        return 1;
    }

    if args.interactive == Interactive::Once {
        let n = args.files.len();
        if args.recursive {
            if !prompt(&format!(
                "remove {} argument{} recursively? ",
                n,
                if n != 1 { "s" } else { "" }
            )) {
                return 0;
            }
        } else if n > 3 {
            if !prompt(&format!("remove {} arguments? ", n)) {
                return 0;
            }
        }
    }

    let mut ok = true;
    let mut purge_paths = Vec::new();
    let mut trash_paths = Vec::new();

    for f in &args.files {
        let (cont, do_del) = validate_one(f, &args);
        if !cont {
            ok = false;
            continue;
        }
        if !do_del {
            continue;
        }
        if args.purge {
            purge_paths.push(f.clone());
        } else {
            trash_paths.push(f.clone());
        }
    }

    for p in &purge_paths {
        if let Err(e) = purge_one(p, args.verbose, args.one_file_system) {
            eprintln!("{}: cannot remove '{}': {}", PROG, p, e);
            ok = false;
        }
    }

    if !trash_paths.is_empty() {
        let errors = backend::trash_files(&trash_paths);
        if !errors.is_empty() {
            for err in &errors {
                eprintln!("{}: {}", PROG, err);
            }
            ok = false;
        } else if args.verbose {
            for p in &trash_paths {
                println!("removed '{}'", p);
            }
        }
    }

    if ok { 0 } else { 1 }
}
