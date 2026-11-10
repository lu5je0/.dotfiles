#[cfg(target_os = "macos")]
use crate::{
    Entry,
    util::{self, Result},
};
use std::collections::BTreeMap;
#[cfg(target_os = "macos")]
use std::{
    ffi::{CStr, CString},
    fs,
    os::unix::{ffi::OsStrExt, fs::MetadataExt},
    path::{Path, PathBuf},
};
#[cfg(target_os = "macos")]
unsafe extern "C" {
    fn qtrash_mac_trash(path: *const libc::c_char, message: *mut *mut libc::c_char) -> libc::c_int;
}
#[cfg(target_os = "macos")]
pub fn trash(path: &Path) -> Result<()> {
    let full = util::absolute(path).map_err(|e| e.to_string())?;
    let path_c = CString::new(full.as_os_str().as_bytes()).map_err(|e| e.to_string())?;
    let mut error = std::ptr::null_mut();
    // The shim bounds Objective-C lifetimes with an autorelease pool and only
    // exports a malloc-owned error string, never an Objective-C object.
    unsafe {
        if qtrash_mac_trash(path_c.as_ptr(), &mut error) == 0 {
            return Ok(());
        }
        let message = if error.is_null() {
            "Foundation trash operation failed".into()
        } else {
            let value = CStr::from_ptr(error).to_string_lossy().into_owned();
            libc::free(error.cast());
            value
        };
        Err(format!("cannot trash '{}': {message}", path.display()))
    }
}
fn utf16_be(bytes: &[u8]) -> String {
    String::from_utf16_lossy(
        &bytes
            .chunks_exact(2)
            .map(|b| u16::from_be_bytes([b[0], b[1]]))
            .collect::<Vec<_>>(),
    )
}
fn putback(data: &[u8]) -> BTreeMap<String, (String, String)> {
    let mut parts: BTreeMap<String, [Option<String>; 2]> = BTreeMap::new();
    for (which, marker) in [b"ptbL", b"ptbN"].iter().enumerate() {
        for (idx, window) in data.windows(4).enumerate() {
            if window != *marker || data.get(idx + 4..idx + 8) != Some(b"ustr") {
                continue;
            }
            let Some(len) = data
                .get(idx + 8..idx + 12)
                .and_then(|b| b.try_into().ok())
                .map(u32::from_be_bytes)
            else {
                continue;
            };
            let Some(end) = (len as usize)
                .checked_mul(2)
                .and_then(|n| (idx + 12).checked_add(n))
            else {
                continue;
            };
            let Some(value) = data.get(idx + 12..end) else {
                continue;
            };
            for n in 1..300 {
                let Some(start) = idx.checked_sub(n * 2 + 4) else {
                    break;
                };
                let len = u32::from_be_bytes(data[start..start + 4].try_into().unwrap()) as usize;
                if len == n {
                    let name = utf16_be(&data[start + 4..idx]);
                    parts.entry(name).or_default()[which] = Some(utf16_be(value));
                    break;
                }
            }
        }
    }
    parts
        .into_iter()
        .filter_map(|(name, [dir, file])| Some((name, (dir?, file?))))
        .collect()
}
#[cfg(target_os = "macos")]
pub fn scan() -> Vec<Entry> {
    let Ok(home) = util::home() else {
        return Vec::new();
    };
    let trash = home.join(".Trash");
    let putback = putback(&fs::read(trash.join(".DS_Store")).unwrap_or_default());
    let entries = match fs::read_dir(&trash) {
        Ok(e) => e,
        Err(e) => {
            if e.kind() != std::io::ErrorKind::NotFound {
                eprintln!("q-trash: cannot read ~/.Trash: {e} (check terminal Full Disk Access)");
            }
            return Vec::new();
        }
    };
    let mut out = Vec::new();
    for file in entries.flatten() {
        let name = file.file_name();
        if name == ".DS_Store" || name == ".Trashes" {
            continue;
        }
        let Ok(meta) = fs::symlink_metadata(file.path()) else {
            continue;
        };
        let original = name
            .to_str()
            .and_then(|s| putback.get(s))
            .map(|(dir, name)| PathBuf::from(format!("/{dir}{name}")))
            .unwrap_or_else(|| PathBuf::from(&name));
        out.push(Entry {
            original,
            date: util::date(meta.ctime()),
            order: meta.ctime() as i128 * 1_000_000_000 + meta.ctime_nsec() as i128,
            trash: trash.clone(),
            info: None,
            file: file.path(),
        });
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    fn record(name: &str, marker: &[u8], value: &str) -> Vec<u8> {
        let mut out = Vec::new();
        out.extend((name.encode_utf16().count() as u32).to_be_bytes());
        for unit in name.encode_utf16() {
            out.extend(unit.to_be_bytes());
        }
        out.extend(marker);
        out.extend(b"ustr");
        out.extend((value.encode_utf16().count() as u32).to_be_bytes());
        for unit in value.encode_utf16() {
            out.extend(unit.to_be_bytes());
        }
        out
    }
    #[test]
    fn putback_records_and_truncation() {
        let mut data = record("中文.txt", b"ptbL", "Users/test/");
        data.extend(record("中文.txt", b"ptbN", "原名.txt"));
        assert_eq!(
            putback(&data)["中文.txt"],
            ("Users/test/".into(), "原名.txt".into())
        );
        data.pop();
        assert!(putback(&data).is_empty());
    }
}
