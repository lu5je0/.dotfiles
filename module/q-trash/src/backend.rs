#[cfg(target_os = "macos")]
use crate::macos;
#[cfg(target_os = "linux")]
use crate::windows;
use crate::{Entry, freedesktop, util};
use std::{
    collections::HashSet,
    path::{Path, PathBuf},
};

pub fn trash(paths: &[PathBuf]) -> Vec<String> {
    let mut errors = Vec::new();
    #[cfg(target_os = "linux")]
    let mut win_paths = Vec::new();
    #[cfg(target_os = "linux")]
    let win_mounts = windows::native_mounts();
    for path in paths {
        #[cfg(target_os = "linux")]
        if windows::is_native(path, &win_mounts) {
            win_paths.push(path.clone());
            continue;
        }
        #[cfg(target_os = "linux")]
        let result = freedesktop::trash(path);
        #[cfg(target_os = "macos")]
        let result = macos::trash(path);
        if let Err(e) = result {
            errors.push(e);
        }
    }
    #[cfg(target_os = "linux")]
    if !win_paths.is_empty() {
        if let Err(e) = windows::trash(&win_paths) {
            errors.push(e);
        }
    }
    errors
}
pub fn scan(specific: Option<&Path>, current_disk: bool) -> util::Result<Vec<Entry>> {
    let mut items = freedesktop::scan(specific);
    if specific.is_none() {
        #[cfg(target_os = "linux")]
        items.extend(windows::scan());
        #[cfg(target_os = "macos")]
        items.extend(macos::scan());
    }
    if current_disk {
        let disk = util::volume_dir(&std::env::current_dir().map_err(|e| e.to_string())?)
            .map_err(|e| e.to_string())?;
        items.retain(|t| freedesktop::guess_volume(&t.trash) == disk);
    }
    let mut seen = HashSet::new();
    items.retain(|t| seen.insert(t.file.clone()));
    items.sort_by(|a, b| (&a.date, a.order, &a.file).cmp(&(&b.date, b.order, &b.file)));
    Ok(items)
}
