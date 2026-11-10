use std::{
    env,
    ffi::{CString, OsStr, OsString},
    fs,
    io::{self, Write},
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::MetadataExt,
    },
    path::{Component, Path, PathBuf},
};

pub type Result<T> = std::result::Result<T, String>;
pub fn home() -> Result<PathBuf> {
    env::var_os("HOME")
        .filter(|s| !s.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| "HOME is not set".into())
}
pub fn absolute(path: &Path) -> io::Result<PathBuf> {
    let full = if path.is_absolute() {
        path.to_owned()
    } else {
        env::current_dir()?.join(path)
    };
    let mut out = PathBuf::new();
    for part in full.components() {
        match part {
            Component::ParentDir => {
                out.pop();
            }
            Component::CurDir => {}
            other => out.push(other.as_os_str()),
        }
    }
    Ok(out)
}
// Resolve ancestors without dereferencing the final entry (which may be a
// symlink or not exist yet). Used before any destructive restore overwrite.
pub fn location(path: &Path) -> io::Result<PathBuf> {
    let full = absolute(path)?;
    let mut parent = full.parent().unwrap_or(Path::new("/")).to_owned();
    let mut tail = vec![full.file_name().unwrap_or(OsStr::new("")).to_owned()];
    loop {
        match fs::canonicalize(&parent) {
            Ok(mut resolved) => {
                for component in tail.iter().rev() {
                    resolved.push(component);
                }
                return Ok(resolved);
            }
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                tail.push(parent.file_name().ok_or(e)?.to_owned());
                parent.pop();
            }
            Err(e) => return Err(e),
        }
    }
}
pub fn exists(path: &Path) -> bool {
    fs::symlink_metadata(path).is_ok()
}
pub fn volume_dir(path: &Path) -> io::Result<PathBuf> {
    let mut current = fs::canonicalize(path)?;
    let dev = fs::metadata(&current)?.dev();
    while let Some(parent) = current.parent() {
        if fs::metadata(parent)?.dev() != dev {
            break;
        }
        current = parent.to_owned();
    }
    Ok(current)
}
pub fn volume(path: &Path) -> io::Result<PathBuf> {
    let full = absolute(path)?;
    volume_dir(full.parent().unwrap_or(Path::new("/")))
}
pub fn remove(path: &Path, one_fs: bool) -> io::Result<()> {
    let meta = fs::symlink_metadata(path)?;
    if meta.is_dir() {
        remove_tree(path, one_fs.then_some(meta.dev()))
    } else {
        fs::remove_file(path)
    }
}
fn remove_tree(path: &Path, dev: Option<u64>) -> io::Result<()> {
    for entry in fs::read_dir(path)? {
        let entry = entry?;
        let meta = fs::symlink_metadata(entry.path())?;
        if meta.is_dir() {
            if dev.is_some_and(|d| d != meta.dev()) {
                continue;
            }
            remove_tree(&entry.path(), dev)?;
        } else {
            fs::remove_file(entry.path())?;
        }
    }
    fs::remove_dir(path)
}
pub fn prompt(message: &str) -> bool {
    eprint!("{message}");
    let _ = io::stderr().flush();
    input().is_ok_and(|s| s.trim().to_lowercase().starts_with('y'))
}
pub fn input() -> io::Result<String> {
    let mut line = String::new();
    io::stdin().read_line(&mut line)?;
    Ok(line)
}
pub fn now() -> i64 {
    unsafe { libc::time(std::ptr::null_mut()) as i64 }
}
pub fn date(seconds: i64) -> String {
    let seconds = seconds as libc::time_t;
    // localtime_r writes into caller-owned storage; strftime receives its exact capacity.
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        if libc::localtime_r(&seconds, &mut tm).is_null() {
            return String::new();
        }
        let mut buf = [0u8; 32];
        let len = libc::strftime(
            buf.as_mut_ptr().cast(),
            buf.len(),
            c"%Y-%m-%dT%H:%M:%S".as_ptr(),
            &tm,
        );
        String::from_utf8_lossy(&buf[..len]).into_owned()
    }
}
pub fn parse_date(value: &str) -> Option<i64> {
    let value = CString::new(value).ok()?;
    unsafe {
        let mut tm: libc::tm = std::mem::zeroed();
        tm.tm_isdst = -1;
        let end = libc::strptime(value.as_ptr(), c"%Y-%m-%dT%H:%M:%S".as_ptr(), &mut tm);
        if end.is_null() || *end != 0 {
            return None;
        }
        Some(libc::mktime(&mut tm) as i64)
    }
}
pub fn encode(path: &Path) -> String {
    let mut out = String::new();
    for &b in path.as_os_str().as_bytes() {
        if b.is_ascii_alphanumeric() || b"/-_.~".contains(&b) {
            out.push(b as char);
        } else {
            use std::fmt::Write;
            write!(out, "%{b:02X}").unwrap();
        }
    }
    out
}
pub fn decode(value: &[u8]) -> Option<OsString> {
    let mut out = Vec::new();
    let mut i = 0;
    while i < value.len() {
        if value[i] == b'%' {
            let hex = std::str::from_utf8(value.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(value[i]);
            i += 1;
        }
    }
    if out.contains(&0) {
        return None;
    }
    Some(OsString::from_vec(out))
}
pub fn append(value: &OsStr, suffix: &str) -> OsString {
    let mut out = value.to_owned();
    out.push(suffix);
    out
}

// The exclusive rename is the final authority, including when another process
// creates the destination after our collision/overwrite checks.
pub fn rename_exclusive(from: &Path, to: &Path) -> io::Result<()> {
    let from = CString::new(from.as_os_str().as_bytes())?;
    let to = CString::new(to.as_os_str().as_bytes())?;
    // musl static builds may lack the renameat2 libc symbol; call the kernel directly.
    #[cfg(target_os = "linux")]
    let result = unsafe {
        libc::syscall(
            libc::SYS_renameat2,
            libc::AT_FDCWD,
            from.as_ptr(),
            libc::AT_FDCWD,
            to.as_ptr(),
            libc::RENAME_NOREPLACE,
        )
    };
    #[cfg(target_os = "macos")]
    let result = unsafe { libc::renamex_np(from.as_ptr(), to.as_ptr(), libc::RENAME_EXCL) };
    if result == 0 {
        Ok(())
    } else {
        Err(io::Error::last_os_error())
    }
}
pub fn error_text(error: &io::Error) -> String {
    match error.kind() {
        io::ErrorKind::NotFound => "No such file or directory".into(),
        io::ErrorKind::PermissionDenied => "Permission denied".into(),
        io::ErrorKind::DirectoryNotEmpty => "Directory not empty".into(),
        io::ErrorKind::IsADirectory => "Is a directory".into(),
        _ => error.to_string(),
    }
}
