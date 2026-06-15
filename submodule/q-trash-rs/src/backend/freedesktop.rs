use crate::model::TrashedFile;
use chrono::Local;
use percent_encoding::{percent_decode_str, utf8_percent_encode, AsciiSet, CONTROLS};
use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};

const ENCODE_SET: &AsciiSet = &CONTROLS
    .add(b' ')
    .add(b'"')
    .add(b'#')
    .add(b'%')
    .add(b'<')
    .add(b'>')
    .add(b'?')
    .add(b'[')
    .add(b']')
    .add(b'^')
    .add(b'`')
    .add(b'{')
    .add(b'|')
    .add(b'}');

fn home_trash_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_DATA_HOME") {
        return PathBuf::from(xdg).join("Trash");
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    PathBuf::from(home).join(".local/share/Trash")
}

fn volume_of(path: &Path) -> PathBuf {
    let abs = fs::canonicalize(path.parent().unwrap_or(Path::new("/"))).unwrap_or_else(|_| PathBuf::from("/"));
    let dev = match fs::metadata(&abs) {
        Ok(m) => m.dev(),
        Err(_) => return abs,
    };
    let mut cur = abs;
    loop {
        let up = match cur.parent() {
            Some(p) if p != cur => p.to_path_buf(),
            _ => return cur,
        };
        match fs::metadata(&up) {
            Ok(m) if m.dev() != dev => return cur,
            Err(_) => return cur,
            _ => cur = up,
        }
    }
}

fn is_safe_top_trash(top_trash: &Path) -> bool {
    if top_trash.is_symlink() {
        return false;
    }
    match fs::metadata(top_trash) {
        Ok(m) => m.is_dir() && (m.permissions().mode() & 0o1000) != 0,
        Err(_) => false,
    }
}

fn discover_trash_dirs() -> Vec<(PathBuf, PathBuf)> {
    let uid = unsafe { libc::getuid() };
    let mut results = Vec::new();

    let ht = home_trash_dir();
    if ht.join("info").is_dir() {
        let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
        results.push((ht, volume_of(Path::new(&home))));
    }

    #[cfg(target_os = "linux")]
    {
        if let Ok(content) = fs::read_to_string("/proc/self/mounts") {
            for line in content.lines() {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if parts.len() >= 2 {
                    let mp = PathBuf::from(decode_octal(parts[1]));
                    let top_trash = mp.join(".Trash");
                    if is_safe_top_trash(&top_trash) {
                        let d = top_trash.join(uid.to_string());
                        if d.join("info").is_dir() {
                            results.push((d, mp.clone()));
                        }
                    }
                    let d = mp.join(format!(".Trash-{}", uid));
                    if !d.is_symlink()
                        && d.join("info").is_dir()
                        && !results.iter().any(|(td, _)| td == &d)
                    {
                        results.push((d, mp));
                    }
                }
            }
        }
    }

    results
}

#[cfg(target_os = "linux")]
fn decode_octal(s: &str) -> String {
    let mut result = String::with_capacity(s.len());
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\' && i + 3 < bytes.len() {
            if let Ok(val) = u8::from_str_radix(
                std::str::from_utf8(&bytes[i + 1..i + 4]).unwrap_or(""),
                8,
            ) {
                result.push(val as char);
                i += 4;
                continue;
            }
        }
        result.push(bytes[i] as char);
        i += 1;
    }
    result
}

fn parse_trashinfo(info_path: &Path, volume_root: &Path) -> Option<TrashedFile> {
    let content = fs::read_to_string(info_path).ok()?;
    let mut path_val: Option<String> = None;
    let mut date_val = String::new();

    for line in content.lines() {
        if let Some(rest) = line.strip_prefix("Path=") {
            path_val = Some(percent_decode_str(rest).decode_utf8_lossy().into_owned());
        } else if let Some(rest) = line.strip_prefix("DeletionDate=") {
            date_val = rest.to_string();
        }
    }

    let path_val = path_val?;
    let original = if Path::new(&path_val).is_absolute() {
        path_val
    } else {
        volume_root.join(&path_val).to_string_lossy().into_owned()
    };

    let info_dir = info_path.parent()?;
    let trash_dir = info_dir.parent()?.to_path_buf();
    let mut name = info_path.file_name()?.to_string_lossy().into_owned();
    if name.ends_with(".trashinfo") {
        name = name[..name.len() - 10].to_string();
    }
    let files_path = trash_dir.join("files").join(&name);

    Some(TrashedFile {
        original_path: original,
        deletion_date: date_val,
        trash_dir,
        info_path: info_path.to_path_buf(),
        files_path,
        name,
    })
}

pub fn scan() -> Vec<TrashedFile> {
    let mut results = Vec::new();
    for (trash_dir, volume_root) in discover_trash_dirs() {
        let info_dir = trash_dir.join("info");
        let entries = match fs::read_dir(&info_dir) {
            Ok(e) => e,
            Err(_) => continue,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.extension().and_then(|e| e.to_str()) != Some("trashinfo") {
                continue;
            }
            if let Some(tf) = parse_trashinfo(&path, &volume_root) {
                results.push(tf);
            }
        }
    }
    results
}

fn pick_trash_dir(file_path: &Path) -> Result<(PathBuf, PathBuf, bool), String> {
    let file_vol = volume_of(file_path);
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let home_path = Path::new(&home);
    if home_path.exists() && volume_of(home_path) == file_vol {
        return Ok((home_trash_dir(), file_vol, true));
    }

    let uid = unsafe { libc::getuid() };
    let top_trash = file_vol.join(".Trash");
    if is_safe_top_trash(&top_trash) {
        let d = top_trash.join(uid.to_string());
        return Ok((d, file_vol, false));
    }

    Ok((file_vol.join(format!(".Trash-{}", uid)), file_vol, false))
}

fn ensure_trash_dirs(trash_dir: &Path) -> Result<(), String> {
    for sub in &["", "files", "info"] {
        let d = trash_dir.join(sub);
        fs::create_dir_all(&d).map_err(|e| format!("cannot create '{}': {}", d.display(), e))?;
        fs::set_permissions(&d, fs::Permissions::from_mode(0o700))
            .map_err(|e| format!("cannot set permissions on '{}': {}", d.display(), e))?;
    }
    Ok(())
}

fn reserve_info_file(info_dir: &Path, base_name: &str) -> Result<(String, PathBuf), String> {
    for n in 1..=10000 {
        let name = if n == 1 {
            base_name.to_string()
        } else {
            format!("{}_{}", base_name, n)
        };
        let info_path = info_dir.join(format!("{}.trashinfo", name));
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&info_path)
        {
            Ok(_) => return Ok((name, info_path)),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("cannot create '{}': {}", info_path.display(), e)),
        }
    }
    Err(format!("too many name collisions in {}", info_dir.display()))
}

pub fn trash(paths: &[String]) -> Vec<String> {
    let mut errors = Vec::new();
    for path in paths {
        if let Err(e) = trash_one(path) {
            errors.push(format!("cannot remove '{}': {}", path, e));
        }
    }
    errors
}

fn trash_one(path: &str) -> Result<(), String> {
    let abs_path = fs::canonicalize(path).map_err(|e| e.to_string())?;
    let (trash_dir, volume_root, is_absolute) = pick_trash_dir(&abs_path)?;

    ensure_trash_dirs(&trash_dir)?;

    let base_name = abs_path
        .file_name()
        .map(|n| n.to_string_lossy().into_owned())
        .unwrap_or_else(|| "_".to_string());

    let info_dir = trash_dir.join("info");
    let files_dir = trash_dir.join("files");
    let (name, info_path) = reserve_info_file(&info_dir, &base_name)?;
    let dest = files_dir.join(&name);

    let rel_path = if is_absolute {
        abs_path.to_string_lossy().into_owned()
    } else {
        let vr = volume_root.to_string_lossy();
        let ap = abs_path.to_string_lossy();
        let prefix = vr.trim_end_matches('/');
        ap.strip_prefix(prefix)
            .and_then(|s| s.strip_prefix('/'))
            .unwrap_or(&ap)
            .to_string()
    };

    let encoded = utf8_percent_encode(&rel_path, ENCODE_SET).to_string();
    let now = Local::now().format("%Y-%m-%dT%H:%M:%S").to_string();
    let body = format!("[Trash Info]\nPath={}\nDeletionDate={}\n", encoded, now);

    fs::write(&info_path, &body).map_err(|e| {
        let _ = fs::remove_file(&info_path);
        format!("cannot write trashinfo: {}", e)
    })?;

    if let Err(e) = fs::rename(&abs_path, &dest) {
        let _ = fs::remove_file(&info_path);
        if e.raw_os_error() == Some(libc::EXDEV) {
            return Err(format!(
                "'{}' lives on a different volume. Use --purge to delete permanently.",
                path
            ));
        }
        return Err(format!("cannot move: {}", e));
    }

    Ok(())
}
