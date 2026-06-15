use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct TrashedFile {
    pub original_path: String,
    pub deletion_date: String,
    pub trash_dir: PathBuf,
    pub info_path: PathBuf,
    pub files_path: PathBuf,
    pub name: String,
}
