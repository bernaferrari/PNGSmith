use crate::Error;

const SIGNATURE: &[u8; 8] = b"\x89PNG\r\n\x1a\n";

/// Copies metadata whose representation remains valid after converting image data
/// to an indexed PNG. Image-dependent chunks (such as bKGD, hIST and sBIT) are
/// deliberately excluded because their payload depends on the original color type.
pub fn copy_compatible_chunks(source: &[u8], candidate: &[u8]) -> Result<Vec<u8>, Error> {
    let metadata = chunks(source)?
        .into_iter()
        .filter(|chunk| is_compatible_metadata(chunk.kind))
        .map(|chunk| chunk.raw)
        .collect::<Vec<_>>();
    if metadata.is_empty() {
        return Ok(candidate.to_vec());
    }
    let candidate_chunks = chunks(candidate)?;
    let ihdr = candidate_chunks
        .first()
        .filter(|chunk| chunk.kind == *b"IHDR")
        .ok_or_else(|| Error::Decode("candidate PNG has no IHDR chunk".into()))?;
    let mut output =
        Vec::with_capacity(candidate.len() + metadata.iter().map(|v| v.len()).sum::<usize>());
    output.extend_from_slice(SIGNATURE);
    output.extend_from_slice(ihdr.raw);
    for chunk in metadata {
        output.extend_from_slice(chunk);
    }
    for chunk in candidate_chunks.into_iter().skip(1) {
        output.extend_from_slice(chunk.raw);
    }
    Ok(output)
}

struct Chunk<'a> {
    kind: [u8; 4],
    raw: &'a [u8],
}

fn chunks(png: &[u8]) -> Result<Vec<Chunk<'_>>, Error> {
    if !png.starts_with(SIGNATURE) {
        return Err(Error::Decode("invalid PNG signature".into()));
    }
    let mut offset = SIGNATURE.len();
    let mut result = Vec::new();
    while offset < png.len() {
        if png.len() - offset < 12 {
            return Err(Error::Decode("truncated PNG chunk".into()));
        }
        let length = u32::from_be_bytes(png[offset..offset + 4].try_into().unwrap()) as usize;
        let end = offset
            .checked_add(12)
            .and_then(|n| n.checked_add(length))
            .ok_or_else(|| Error::Decode("PNG chunk length overflow".into()))?;
        if end > png.len() {
            return Err(Error::Decode("truncated PNG chunk payload".into()));
        }
        let kind: [u8; 4] = png[offset + 4..offset + 8].try_into().unwrap();
        result.push(Chunk {
            kind,
            raw: &png[offset..end],
        });
        offset = end;
        if kind == *b"IEND" {
            break;
        }
    }
    Ok(result)
}

fn is_compatible_metadata(kind: [u8; 4]) -> bool {
    matches!(
        &kind,
        b"cHRM"
            | b"gAMA"
            | b"iCCP"
            | b"sRGB"
            | b"eXIf"
            | b"pHYs"
            | b"tIME"
            | b"tEXt"
            | b"zTXt"
            | b"iTXt"
            | b"sPLT"
            | b"oFFs"
            | b"pCAL"
            | b"sCAL"
    ) || (kind[0].is_ascii_lowercase() && kind[3].is_ascii_lowercase())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn png_with_text() -> Vec<u8> {
        let mut bytes = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut bytes), 1, 1);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        encoder
            .add_text_chunk("Author".into(), "PNG Smith".into())
            .unwrap();
        let mut writer = encoder.write_header().unwrap();
        writer.write_image_data(&[1, 2, 3]).unwrap();
        drop(writer);
        bytes
    }

    #[test]
    fn compatible_text_metadata_is_copied() {
        let source = png_with_text();
        let merged = copy_compatible_chunks(&source, &source).unwrap();
        let names: Vec<_> = chunks(&merged)
            .unwrap()
            .into_iter()
            .map(|c| c.kind)
            .collect();
        assert_eq!(names.iter().filter(|&&n| n == *b"tEXt").count(), 2);
    }
}
