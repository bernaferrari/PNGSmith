use crate::Error;
use std::io::Cursor;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecodedImage {
    pub width: u32,
    pub height: u32,
    pub rgba16: Vec<[u16; 4]>,
}

pub fn decode(source: &[u8], max_bytes: usize) -> Result<DecodedImage, Error> {
    let mut decoder = png::Decoder::new(Cursor::new(source));
    decoder.set_transformations(png::Transformations::EXPAND);
    decoder.set_limits(png::Limits { bytes: max_bytes });
    let mut reader = decoder.read_info()?;
    let size = reader
        .output_buffer_size()
        .ok_or_else(|| Error::Decode("image buffer is too large".into()))?;
    if size > max_bytes {
        return Err(Error::Decode(
            "decompressed image exceeds configured limit".into(),
        ));
    }
    let mut bytes = vec![0; size];
    let info = reader.next_frame(&mut bytes)?;
    let data = &bytes[..info.buffer_size()];
    let depth = info.bit_depth;
    let color = info.color_type;
    let channels = color.samples();
    let sample_count = (info.width as usize)
        .checked_mul(info.height as usize)
        .and_then(|n| n.checked_mul(channels))
        .ok_or_else(|| Error::Decode("image dimensions overflow".into()))?;
    let samples: Vec<u16> = match depth {
        png::BitDepth::Eight => {
            if data.len() != sample_count {
                return Err(Error::Decode("unexpected decoded byte count".into()));
            }
            data.iter().map(|&v| u16::from(v) * 257).collect()
        }
        png::BitDepth::Sixteen => {
            if data.len() != sample_count * 2 {
                return Err(Error::Decode("unexpected decoded byte count".into()));
            }
            data.chunks_exact(2)
                .map(|v| u16::from_be_bytes([v[0], v[1]]))
                .collect()
        }
        _ => {
            return Err(Error::Decode(
                "decoder returned an unexpanded bit depth".into(),
            ));
        }
    };
    let rgba16 = samples
        .chunks_exact(channels)
        .map(|pixel| match color {
            png::ColorType::Grayscale => [pixel[0], pixel[0], pixel[0], u16::MAX],
            png::ColorType::GrayscaleAlpha => [pixel[0], pixel[0], pixel[0], pixel[1]],
            png::ColorType::Rgb => [pixel[0], pixel[1], pixel[2], u16::MAX],
            png::ColorType::Rgba => [pixel[0], pixel[1], pixel[2], pixel[3]],
            png::ColorType::Indexed => unreachable!("EXPAND must expand indexed pixels"),
        })
        .collect();
    Ok(DecodedImage {
        width: info.width,
        height: info.height,
        rgba16,
    })
}
