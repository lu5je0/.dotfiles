pub mod freedesktop;
#[cfg(target_os = "macos")]
pub mod macos;

use crate::model::TrashedFile;
use std::collections::HashSet;

pub fn scan_trash() -> Vec<TrashedFile> {
    let mut results = Vec::new();
    let mut seen = HashSet::new();

    #[cfg(target_os = "macos")]
    {
        for tf in macos::scan() {
            if seen.insert(tf.files_path.clone()) {
                results.push(tf);
            }
        }
    }

    for tf in freedesktop::scan() {
        if seen.insert(tf.files_path.clone()) {
            results.push(tf);
        }
    }

    results.sort_by(|a, b| (&a.deletion_date, &a.files_path).cmp(&(&b.deletion_date, &b.files_path)));
    results
}

pub fn trash_files(paths: &[String]) -> Vec<String> {
    if paths.is_empty() {
        return vec![];
    }

    #[cfg(target_os = "macos")]
    {
        return macos::trash(paths);
    }

    #[cfg(not(target_os = "macos"))]
    {
        return freedesktop::trash(paths);
    }
}
