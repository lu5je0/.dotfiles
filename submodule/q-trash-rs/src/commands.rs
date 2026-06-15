use crate::backend;
use crate::model::TrashedFile;
use std::fs;
use std::io::Write;
use std::path::Path;

fn human_size(n: u64) -> String {
    let mut size = n as f64;
    for unit in &["B", "KB", "MB", "GB", "TB"] {
        if size.abs() < 1024.0 {
            return if *unit == "B" {
                format!("{} {}", n, unit)
            } else {
                format!("{:.1} {}", size, unit)
            };
        }
        size /= 1024.0;
    }
    format!("{:.1} PB", size)
}

fn dir_size(path: &Path) -> u64 {
    let mut total = 0u64;
    if let Ok(entries) = fs::read_dir(path) {
        for entry in entries.flatten() {
            let p = entry.path();
            if let Ok(m) = p.symlink_metadata() {
                if m.is_dir() && !m.is_symlink() {
                    total += dir_size(&p);
                } else {
                    total += m.len();
                }
            }
        }
    }
    total
}

pub fn cmd_list(filter: Option<&str>) -> i32 {
    let items = backend::scan_trash();
    let items: Vec<&TrashedFile> = if let Some(f) = filter {
        let fp = fs::canonicalize(f)
            .unwrap_or_else(|_| std::path::PathBuf::from(f))
            .to_string_lossy()
            .into_owned();
        items
            .iter()
            .filter(|t| {
                t.original_path == fp
                    || t.original_path.starts_with(&format!(
                        "{}/",
                        fp.trim_end_matches('/')
                    ))
            })
            .collect()
    } else {
        items.iter().collect()
    };

    if items.is_empty() {
        eprintln!("No trashed files.");
        return 0;
    }

    for t in &items {
        println!("{}  {}", t.deletion_date, t.original_path);
    }
    0
}

pub fn cmd_restore(args: &[String]) -> i32 {
    let mut restore_all = false;
    let mut overwrite = false;
    let mut remaining = Vec::new();

    for arg in args {
        match arg.as_str() {
            "--all" => restore_all = true,
            "--overwrite" => overwrite = true,
            _ => remaining.push(arg.clone()),
        }
    }

    let explicit_path = !remaining.is_empty();
    let filter_path: Option<String> = if explicit_path {
        Some(
            fs::canonicalize(&remaining[0])
                .unwrap_or_else(|_| std::path::PathBuf::from(&remaining[0]))
                .to_string_lossy()
                .into_owned(),
        )
    } else {
        None
    };

    let mut items = backend::scan_trash();

    let exact: Vec<&TrashedFile> = filter_path
        .as_ref()
        .map(|fp| items.iter().filter(|t| t.original_path == *fp).collect())
        .unwrap_or_default();

    if explicit_path && !exact.is_empty() && !restore_all {
        return do_restore(exact.last().unwrap(), overwrite);
    }

    if restore_all {
        if let Some(fp) = &filter_path {
            items.retain(|t| {
                t.original_path == *fp
                    || t.original_path
                        .starts_with(&format!("{}/", fp.trim_end_matches('/')))
            });
        }
        if items.is_empty() {
            let msg = filter_path
                .map(|fp| format!("No files trashed from '{}'", fp))
                .unwrap_or_else(|| "No trashed files.".to_string());
            eprintln!("{}", msg);
            return 1;
        }
        let mut seen = std::collections::HashMap::new();
        for t in &items {
            seen.insert(t.original_path.clone(), t);
        }
        let mut ok = true;
        for t in seen.values() {
            if do_restore(t, overwrite) != 0 {
                ok = false;
            }
        }
        return if ok { 0 } else { 1 };
    }

    if let Some(fp) = &filter_path {
        items.retain(|t| {
            t.original_path == *fp
                || t.original_path
                    .starts_with(&format!("{}/", fp.trim_end_matches('/')))
        });
    }
    if items.is_empty() {
        let msg = filter_path
            .map(|fp| format!("No files trashed from '{}'", fp))
            .unwrap_or_else(|| "No trashed files.".to_string());
        eprintln!("{}", msg);
        return 1;
    }

    for (idx, t) in items.iter().enumerate() {
        eprintln!("  {:3}  {}  {}", idx, t.deletion_date, t.original_path);
    }
    eprint!("What to restore [0..{}, all, quit]: ", items.len() - 1);
    let _ = std::io::stderr().flush();

    let mut line = String::new();
    if std::io::stdin().read_line(&mut line).unwrap_or(0) == 0 {
        return 1;
    }
    let line = line.trim();
    if line.is_empty() || line == "quit" || line == "q" {
        return 0;
    }
    if line == "all" {
        let mut ok = true;
        for t in &items {
            if do_restore(t, overwrite) != 0 {
                ok = false;
            }
        }
        return if ok { 0 } else { 1 };
    }

    let indices: Result<Vec<usize>, _> = line
        .replace(',', " ")
        .split_whitespace()
        .map(|s| s.parse::<usize>())
        .collect();

    match indices {
        Err(_) => {
            eprintln!("q-trash: invalid input");
            1
        }
        Ok(indices) => {
            let mut ok = true;
            for idx in indices {
                if idx >= items.len() {
                    eprintln!("q-trash: index {} out of range", idx);
                    return 1;
                }
                if do_restore(&items[idx], overwrite) != 0 {
                    ok = false;
                }
            }
            if ok { 0 } else { 1 }
        }
    }
}

fn do_restore(t: &TrashedFile, overwrite: bool) -> i32 {
    let dest = &t.original_path;

    if !t.files_path.exists() && !t.files_path.is_symlink() {
        eprintln!("q-trash: backup file missing: '{}'", t.files_path.display());
        return 1;
    }

    let dest_path = Path::new(dest);
    if dest_path.exists() || dest_path.is_symlink() {
        if !overwrite {
            eprintln!("q-trash: '{}' already exists (use --overwrite)", dest);
            return 1;
        }
        if dest_path.is_dir() && !dest_path.is_symlink() {
            let _ = fs::remove_dir_all(dest_path);
        } else {
            let _ = fs::remove_file(dest_path);
        }
    }

    if let Some(parent) = dest_path.parent() {
        if !parent.is_dir() {
            let _ = fs::create_dir_all(parent);
        }
    }

    if let Err(e) = fs::rename(&t.files_path, dest_path) {
        eprintln!("q-trash: cannot restore '{}': {}", dest, e);
        return 1;
    }

    if !t.info_path.as_os_str().is_empty() {
        let _ = fs::remove_file(&t.info_path);
    }

    println!("Restored: {}", dest);
    0
}

pub fn cmd_empty(args: &[String]) -> i32 {
    let mut days: Option<i64> = None;
    let mut force = false;
    let mut i = 0;

    while i < args.len() {
        match args[i].as_str() {
            "--days" => {
                if i + 1 >= args.len() {
                    eprintln!("q-trash: --days requires an argument");
                    return 1;
                }
                days = match args[i + 1].parse() {
                    Ok(d) => Some(d),
                    Err(_) => {
                        eprintln!("q-trash: invalid --days value");
                        return 1;
                    }
                };
                i += 2;
            }
            s if s.starts_with("--days=") => {
                days = match s[7..].parse() {
                    Ok(d) => Some(d),
                    Err(_) => {
                        eprintln!("q-trash: invalid --days value");
                        return 1;
                    }
                };
                i += 1;
            }
            "-f" | "--force" => {
                force = true;
                i += 1;
            }
            _ => {
                eprintln!("q-trash: unknown argument '{}'", args[i]);
                return 1;
            }
        }
    }

    let mut items = backend::scan_trash();

    if let Some(d) = days {
        let now = chrono::Local::now().naive_local();
        items.retain(|t| {
            if let Ok(dt) = chrono::NaiveDateTime::parse_from_str(&t.deletion_date, "%Y-%m-%dT%H:%M:%S") {
                (now - dt).num_days() >= d
            } else {
                false
            }
        });
    }

    if items.is_empty() {
        println!("Trash is already empty.");
        return 0;
    }

    if !force {
        let msg = format!(
            "Permanently delete {} item{}?{}",
            items.len(),
            if items.len() != 1 { "s" } else { "" },
            days.map(|d| format!(" (older than {} days)", d)).unwrap_or_default()
        );
        eprint!("{} [y/N] ", msg);
        let _ = std::io::stderr().flush();
        let mut line = String::new();
        if std::io::stdin().read_line(&mut line).unwrap_or(0) == 0
            || !line.trim().to_lowercase().starts_with('y')
        {
            println!("Cancelled.");
            return 0;
        }
    }

    let mut deleted = 0;
    for t in &items {
        let fp = &t.files_path;
        let remove_ok = if fp.is_dir() && !fp.is_symlink() {
            fs::remove_dir_all(fp).is_ok()
        } else {
            fs::remove_file(fp).is_ok()
        };
        if !remove_ok {
            eprintln!("q-trash: cannot delete '{}'", fp.display());
            continue;
        }
        if !t.info_path.as_os_str().is_empty() {
            let _ = fs::remove_file(&t.info_path);
        }
        deleted += 1;
    }

    println!(
        "Deleted {} item{}.",
        deleted,
        if deleted != 1 { "s" } else { "" }
    );
    0
}

pub fn cmd_size() -> i32 {
    let items = backend::scan_trash();
    if items.is_empty() {
        println!("All trash directories are empty.");
        return 0;
    }

    let mut sized: Vec<(u64, &TrashedFile)> = Vec::new();
    let mut total_size = 0u64;

    for t in &items {
        let size = if let Ok(m) = t.files_path.symlink_metadata() {
            if m.is_dir() && !t.files_path.is_symlink() {
                dir_size(&t.files_path)
            } else {
                m.len()
            }
        } else {
            continue;
        };
        total_size += size;
        sized.push((size, t));
    }

    sized.sort_by(|a, b| b.0.cmp(&a.0));

    for (size, t) in &sized {
        println!(
            "{:>10}  {}  {}",
            human_size(*size),
            t.deletion_date,
            t.original_path
        );
    }
    println!(
        "{:>10}  Total ({} item{})",
        human_size(total_size),
        sized.len(),
        if sized.len() != 1 { "s" } else { "" }
    );
    0
}
