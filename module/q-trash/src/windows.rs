use crate::{
    Entry, freedesktop,
    util::{self, Result},
};
use std::{
    fs,
    path::{Path, PathBuf},
    process::Command,
};
fn is_wsl() -> bool {
    fs::read_to_string("/proc/version").is_ok_and(|s| s.to_lowercase().contains("microsoft"))
}
pub fn native_mounts() -> Vec<PathBuf> {
    if !is_wsl() {
        return Vec::new();
    }
    freedesktop::mounts()
        .into_iter()
        .filter(|(_, kind)| matches!(kind.as_str(), "drvfs" | "9p" | "virtiofs"))
        .map(|(p, _)| p)
        .collect()
}
pub fn is_native(path: &Path, mounts: &[PathBuf]) -> bool {
    !mounts.is_empty() && util::volume(path).is_ok_and(|v| mounts.contains(&v))
}
pub fn trash(paths: &[PathBuf]) -> Result<()> {
    let mut literals = Vec::new();
    for path in paths {
        let full = util::absolute(path).map_err(|e| e.to_string())?;
        let out = Command::new("wslpath")
            .arg("-w")
            .arg(&full)
            .output()
            .map_err(|e| format!("wslpath: {e}"))?;
        if !out.status.success() {
            return Err(format!("wslpath failed for '{}'", path.display()));
        }
        let value = String::from_utf8(out.stdout).map_err(|e| e.to_string())?;
        literals.push(format!(
            "'{}'",
            value.trim_end_matches(['\r', '\n']).replace('\'', "''")
        ));
    }
    let script = format!(
        "$ErrorActionPreference='Stop'; Add-Type -AssemblyName Microsoft.VisualBasic; $failed=@(); $paths=@({}); foreach ($p in $paths) {{ try {{ if (Test-Path -LiteralPath $p -PathType Container) {{ [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p,'OnlyErrorDialogs','SendToRecycleBin') }} else {{ [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p,'OnlyErrorDialogs','SendToRecycleBin') }} }} catch {{ $failed += \"${{p}}: $($_.Exception.Message)\" }} }}; if ($failed.Count -gt 0) {{ $failed | ForEach-Object {{ [Console]::Error.WriteLine($_) }}; exit 1 }}",
        literals.join(",")
    );
    let args = [
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy",
        "Bypass",
        "-Command",
        &script,
    ];
    let out = Command::new("powershell.exe")
        .args(args)
        .output()
        .or_else(|_| {
            Command::new("/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe")
                .args(args)
                .output()
        })
        .map_err(|e| format!("powershell.exe: {e}"))?;
    if out.status.success() {
        Ok(())
    } else {
        Err(format!(
            "Windows Recycle Bin failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        ))
    }
}
fn parse(data: &[u8]) -> Option<(String, PathBuf, i128)> {
    let version = i64::from_le_bytes(data.get(0..8)?.try_into().ok()?);
    let time = i64::from_le_bytes(data.get(16..24)?.try_into().ok()?);
    let raw = match version {
        1 => data.get(24..544)?,
        2 => {
            let len = u32::from_le_bytes(data.get(24..28)?.try_into().ok()?) as usize;
            data.get(28..28usize.checked_add(len.checked_mul(2)?)?)?
        }
        _ => return None,
    };
    if raw.len() % 2 != 0 {
        return None;
    }
    let units: Vec<u16> = raw
        .chunks_exact(2)
        .map(|b| u16::from_le_bytes([b[0], b[1]]))
        .take_while(|n| *n != 0)
        .collect();
    let name = String::from_utf16(&units).ok()?;
    if name.is_empty() {
        return None;
    }
    let b = name.as_bytes();
    let path = if b.len() >= 3 && b[0].is_ascii_alphabetic() && b[1] == b':' && b[2] == b'\\' {
        PathBuf::from(format!(
            "/mnt/{}{}",
            (b[0] as char).to_ascii_lowercase(),
            name[2..].replace('\\', "/")
        ))
    } else {
        return None;
    };
    Some((
        util::date(time / 10_000_000 - 11_644_473_600),
        path,
        time as i128,
    ))
}
pub fn scan() -> Vec<Entry> {
    let mut out = Vec::new();
    for mount in native_mounts() {
        let Ok(sids) = fs::read_dir(mount.join("$Recycle.Bin")) else {
            continue;
        };
        for sid in sids.flatten() {
            let Ok(files) = fs::read_dir(sid.path()) else {
                continue;
            };
            for file in files.flatten() {
                let name = file.file_name();
                let Some(name) = name
                    .to_str()
                    .and_then(|s| s.strip_prefix("$I"))
                    .filter(|s| !s.is_empty())
                else {
                    continue;
                };
                let target = sid.path().join(format!("$R{name}"));
                if !util::exists(&target) {
                    continue;
                }
                let Some((date, original, order)) =
                    fs::read(file.path()).ok().and_then(|b| parse(&b))
                else {
                    continue;
                };
                out.push(Entry {
                    original,
                    date,
                    order,
                    trash: sid.path(),
                    info: Some(file.path()),
                    file: target,
                });
            }
        }
    }
    out
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn metadata_bounds_and_unicode() {
        let name: Vec<u16> = "C:\\中文\\file\0".encode_utf16().collect();
        let mut data = Vec::new();
        data.extend(2i64.to_le_bytes());
        data.extend(1i64.to_le_bytes());
        data.extend(132537600000000000i64.to_le_bytes());
        data.extend((name.len() as u32).to_le_bytes());
        for unit in name {
            data.extend(unit.to_le_bytes());
        }
        assert_eq!(parse(&data).unwrap().1, PathBuf::from("/mnt/c/中文/file"));
        data.pop();
        assert!(parse(&data).is_none());
    }
}
