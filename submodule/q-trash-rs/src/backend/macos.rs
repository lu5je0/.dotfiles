use crate::model::TrashedFile;
use chrono::DateTime;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

fn parse_dsstore_putback(ds_path: &std::path::Path) -> HashMap<String, (String, String)> {
    let data = match fs::read(ds_path) {
        Ok(d) => d,
        Err(_) => return HashMap::new(),
    };

    let mut records: HashMap<String, HashMap<String, String>> = HashMap::new();

    for marker in &[b"ptbL" as &[u8], b"ptbN" as &[u8]] {
        let mut start = 0;
        while let Some(rel) = data[start..].windows(4).position(|w| w == *marker) {
            let idx = start + rel;
            start = idx + 4;
            if idx + 12 > data.len() {
                continue;
            }
            if &data[idx + 4..idx + 8] != b"ustr" {
                continue;
            }
            let str_len = u32::from_be_bytes([
                data[idx + 8], data[idx + 9], data[idx + 10], data[idx + 11],
            ]) as usize;
            let end = idx + 12 + str_len * 2;
            if end > data.len() {
                continue;
            }
            let value = decode_utf16be(&data[idx + 12..end]);

            let mut fname = None;
            for try_len in 1..300usize {
                let name_start = idx.checked_sub(try_len * 2);
                let len_start = name_start.and_then(|ns| ns.checked_sub(4));
                let (name_start, len_start) = match (name_start, len_start) {
                    (Some(ns), Some(ls)) => (ns, ls),
                    _ => break,
                };
                let candidate = u32::from_be_bytes([
                    data[len_start], data[len_start + 1],
                    data[len_start + 2], data[len_start + 3],
                ]) as usize;
                if candidate == try_len {
                    fname = Some(decode_utf16be(&data[name_start..idx]));
                    break;
                }
            }
            if let Some(fname) = fname {
                let marker_str = std::str::from_utf8(marker).unwrap_or("");
                records
                    .entry(fname)
                    .or_default()
                    .insert(marker_str.to_string(), value);
            }
        }
    }

    records
        .into_iter()
        .filter_map(|(name, info)| {
            let l = info.get("ptbL")?.clone();
            let n = info.get("ptbN")?.clone();
            Some((name, (l, n)))
        })
        .collect()
}

fn decode_utf16be(data: &[u8]) -> String {
    let u16s: Vec<u16> = data
        .chunks_exact(2)
        .map(|c| u16::from_be_bytes([c[0], c[1]]))
        .collect();
    String::from_utf16_lossy(&u16s)
}

pub fn scan() -> Vec<TrashedFile> {
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string());
    let trash_dir = PathBuf::from(&home).join(".Trash");
    if !trash_dir.is_dir() {
        return vec![];
    }

    let entries = match fs::read_dir(&trash_dir) {
        Ok(e) => e,
        Err(_) => return vec![],
    };

    let putback = parse_dsstore_putback(&trash_dir.join(".DS_Store"));

    let mut results = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name == ".DS_Store" || name == ".Trashes" {
            continue;
        }
        let files_path = entry.path();
        let meta = match files_path.symlink_metadata() {
            Ok(m) => m,
            Err(_) => continue,
        };

        let mtime = meta
            .modified()
            .ok()
            .and_then(|t| {
                let dur = t.duration_since(std::time::UNIX_EPOCH).ok()?;
                DateTime::from_timestamp(dur.as_secs() as i64, 0).map(|dt| dt.naive_local())
            })
            .map(|dt| dt.format("%Y-%m-%dT%H:%M:%S").to_string())
            .unwrap_or_default();

        let original_path = if let Some((dir, orig_name)) = putback.get(&name) {
            format!("/{}{}", dir, orig_name)
        } else {
            name.clone()
        };

        results.push(TrashedFile {
            original_path,
            deletion_date: mtime,
            trash_dir: trash_dir.clone(),
            info_path: PathBuf::new(),
            files_path,
            name,
        });
    }

    results
}

fn abs_without_resolving(p: &str) -> String {
    let path = std::path::Path::new(p);
    if path.is_absolute() {
        return p.to_string();
    }
    std::env::current_dir()
        .map(|cwd| cwd.join(p).to_string_lossy().into_owned())
        .unwrap_or_else(|_| p.to_string())
}

pub fn trash(paths: &[String]) -> Vec<String> {
    let abs_paths: Vec<String> = paths.iter().map(|p| abs_without_resolving(p)).collect();

    let output = Command::new("trash")
        .args(&abs_paths)
        .output();

    match output {
        Ok(o) if o.status.success() => vec![],
        Ok(o) => {
            let stderr = String::from_utf8_lossy(&o.stderr);
            let stdout = String::from_utf8_lossy(&o.stdout);
            let msg = if !stderr.is_empty() { stderr } else { stdout };
            let last = msg.trim().lines().last().unwrap_or("unknown error");
            vec![format!("macOS trash failed: {}", last)]
        }
        Err(e) => vec![format!("cannot run 'trash' command: {}", e)],
    }
}
