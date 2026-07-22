use crate::Error;
use std::{
    fs,
    io::Write,
    path::{Path, PathBuf},
};

pub fn destination(input: &Path, create_copy: bool, suffix: &str) -> Result<PathBuf, Error> {
    if !create_copy {
        return Ok(input.to_path_buf());
    }
    let stem = input
        .file_stem()
        .and_then(|s| s.to_str())
        .ok_or_else(|| Error::Output("input has no valid UTF-8 filename".into()))?;
    let extension = input.extension().and_then(|s| s.to_str()).unwrap_or("png");
    Ok(input.with_file_name(format!("{stem}{suffix}.{extension}")))
}

pub fn atomic_write(path: &Path, contents: &[u8], source: &Path) -> Result<(), Error> {
    let parent = path
        .parent()
        .ok_or_else(|| Error::Output("output has no parent directory".into()))?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)?;
    temporary.write_all(contents)?;
    temporary.as_file_mut().sync_all()?;
    if let Ok(metadata) = fs::metadata(source) {
        let _ = temporary.as_file().set_permissions(metadata.permissions());
    }
    temporary
        .persist(path)
        .map_err(|error| Error::Io(error.error))?;
    Ok(())
}
