use crate::{
    Entry,
    util::{self, Result},
};
use std::{
    collections::BTreeMap,
    env,
    ffi::{OsStr, OsString},
    fs::{self, OpenOptions},
    io::{self, Write},
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
    },
    path::{Component, Path, PathBuf},
};

pub fn mounts() -> Vec<(PathBuf, String)> {
    #[cfg(target_os = "macos")]
    {
        let mut out = vec![(PathBuf::from("/"), "apfs".into())];
        if let Ok(dirs) = fs::read_dir("/Volumes") {
            out.extend(
                dirs.flatten()
                    .filter(|e| e.path().is_dir())
                    .map(|e| (e.path(), "apfs".into())),
            );
        }
        out
    }
    #[cfg(target_os = "linux")]
    fs::read("/proc/self/mounts")
        .unwrap_or_default()
        .split(|b| *b == b'\n')
        .filter_map(|line| {
            let parts: Vec<_> = line
                .split(|b| b.is_ascii_whitespace())
                .filter(|p| !p.is_empty())
                .collect();
            if parts.len() < 3 {
                return None;
            }
            Some((
                PathBuf::from(OsString::from_vec(decode_mount(parts[1]))),
                String::from_utf8_lossy(parts[2]).into_owned(),
            ))
        })
        .collect()
}
#[cfg(any(target_os = "linux", test))]
pub fn decode_mount(bytes: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'\\'
            && i + 3 < bytes.len()
            && bytes[i + 1..i + 4]
                .iter()
                .all(|b| (b'0'..=b'7').contains(b))
        {
            let val = ((bytes[i + 1] - b'0') as u16) * 64
                + ((bytes[i + 2] - b'0') as u16) * 8
                + (bytes[i + 3] - b'0') as u16;
            if val <= 255 {
                out.push(val as u8);
                i += 4;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    out
}
pub fn home_trash() -> Result<PathBuf> {
    let data = match env::var_os("XDG_DATA_HOME").filter(|p| !p.is_empty()) {
        Some(path) => {
            let path = PathBuf::from(path);
            if !path.is_absolute() {
                return Err("XDG_DATA_HOME must be absolute".into());
            }
            path
        }
        None => util::home()?.join(".local/share"),
    };
    Ok(data.join("Trash"))
}
pub fn safe_top(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok_and(|m| m.is_dir() && m.mode() & 0o1000 != 0)
}
pub fn guess_volume(path: &Path) -> PathBuf {
    let path = fs::canonicalize(path).unwrap_or_else(|_| path.to_owned());
    let parent = path.parent().unwrap_or(Path::new("/"));
    if path
        .file_name()
        .is_some_and(|n| n.as_bytes().starts_with(b".Trash"))
    {
        parent.to_owned()
    } else if parent.file_name() == Some(OsStr::new(".Trash")) {
        parent.parent().unwrap_or(Path::new("/")).to_owned()
    } else {
        util::volume_dir(&path).unwrap_or_else(|_| PathBuf::from("/"))
    }
}
fn ensure_dirs(path: &Path) -> Result<()> {
    for dir in [path.to_owned(), path.join("files"), path.join("info")] {
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&dir)
            .map_err(|e| format!("cannot create '{}': {e}", dir.display()))?;
        let meta = fs::symlink_metadata(&dir).map_err(|e| e.to_string())?;
        if !meta.is_dir() || meta.uid() != unsafe { libc::getuid() } || meta.mode() & 0o077 != 0 {
            return Err(format!(
                "unsafe trash directory '{}' (must be owned by current user, mode 0700, and not a symlink)",
                dir.display()
            ));
        }
    }
    Ok(())
}
pub fn trash(path: &Path) -> Result<()> {
    let full = util::absolute(path).map_err(|e| e.to_string())?;
    let root = util::volume(&full).map_err(|e| e.to_string())?;
    let home = util::home()?;
    let (trash, relative) = if util::volume_dir(&home).ok().as_ref() == Some(&root) {
        (home_trash()?, false)
    } else {
        let top = root.join(".Trash");
        let uid = unsafe { libc::getuid() };
        (
            if safe_top(&top) {
                top.join(uid.to_string())
            } else {
                root.join(format!(".Trash-{uid}"))
            },
            true,
        )
    };
    ensure_dirs(&trash).map_err(|e| {
        format!(
            "cannot use trash dir for '{}': {e}. Use --purge to delete permanently.",
            path.display()
        )
    })?;
    let original = if relative {
        full.strip_prefix(&root).map_err(|e| e.to_string())?
    } else {
        &full
    };
    let body = format!(
        "[Trash Info]\nPath={}\nDeletionDate={}\n",
        util::encode(original),
        util::date(util::now())
    );
    let base = full.file_name().unwrap_or(OsStr::new("_"));
    for n in 1..=10000 {
        let name = if n == 1 {
            base.to_owned()
        } else {
            util::append(base, &format!("_{n}"))
        };
        let info = trash.join("info").join(util::append(&name, ".trashinfo"));
        let dest = trash.join("files").join(&name);
        let mut file = match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&info)
        {
            Ok(f) => f,
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(format!("cannot reserve '{}': {e}", info.display())),
        };
        let result = file
            .write_all(body.as_bytes())
            .and_then(|_| util::rename_exclusive(&full, &dest));
        if let Err(e) = result {
            let _ = fs::remove_file(&info);
            if e.kind() == io::ErrorKind::AlreadyExists {
                continue;
            }
            if e.raw_os_error() == Some(libc::EXDEV) {
                return Err(format!(
                    "'{}' lives on a different volume from its trash dir ('{}'). Use --purge to delete permanently.",
                    path.display(),
                    trash.display()
                ));
            }
            return Err(format!(
                "cannot move '{}': {}",
                path.display(),
                util::error_text(&e)
            ));
        }
        return Ok(());
    }
    Err(format!("too many name collisions in {}", trash.display()))
}
pub fn scan(specific: Option<&Path>) -> Vec<Entry> {
    let mut dirs = BTreeMap::new();
    if let Some(path) = specific {
        dirs.insert(path.to_owned(), guess_volume(path));
    } else {
        if let (Ok(home), Ok(trash)) = (util::home(), home_trash()) {
            dirs.insert(
                trash,
                util::volume_dir(&home).unwrap_or_else(|_| PathBuf::from("/")),
            );
        }
        let uid = unsafe { libc::getuid() };
        for (mount, _) in mounts() {
            let top = mount.join(".Trash");
            if safe_top(&top) {
                dirs.insert(top.join(uid.to_string()), mount.clone());
            }
            let private = mount.join(format!(".Trash-{uid}"));
            if fs::symlink_metadata(&private).is_ok_and(|m| m.is_dir()) {
                dirs.insert(private, mount);
            }
        }
    }
    let mut out = Vec::new();
    for (trash, root) in dirs {
        let Ok(files) = fs::read_dir(trash.join("info")) else {
            continue;
        };
        for entry in files.flatten() {
            let name = entry.file_name();
            let Some(base) = name.as_bytes().strip_suffix(b".trashinfo") else {
                continue;
            };
            if !entry.file_type().is_ok_and(|t| t.is_file()) {
                continue;
            }
            let Ok(content) = fs::read(entry.path()) else {
                continue;
            };
            let mut original = None;
            let mut date = String::new();
            for line in content.split(|b| *b == b'\n') {
                let line = line.strip_suffix(b"\r").unwrap_or(line);
                if let Some(value) = line.strip_prefix(b"Path=") {
                    original = util::decode(value).map(PathBuf::from);
                }
                if let Some(value) = line.strip_prefix(b"DeletionDate=") {
                    date = String::from_utf8_lossy(value).trim_end_matches('\r').into();
                }
            }
            let Some(mut original) = original else {
                continue;
            };
            if original.as_os_str().is_empty() {
                continue;
            }
            if !original.is_absolute() {
                if original
                    .components()
                    .any(|c| matches!(c, Component::ParentDir))
                {
                    continue;
                }
                original = root.join(original);
            }
            out.push(Entry {
                original,
                date,
                order: entry
                    .metadata()
                    .map(|m| m.mtime() as i128 * 1_000_000_000 + m.mtime_nsec() as i128)
                    .unwrap_or(0),
                trash: trash.clone(),
                info: Some(entry.path()),
                file: trash.join("files").join(OsStr::from_bytes(base)),
            });
        }
    }
    out
}
