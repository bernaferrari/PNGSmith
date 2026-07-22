use crate::{
    Error,
    image_data::{DecodedImage, decode},
};
use std::{collections::HashMap, io::Cursor};

pub fn encode(source: &[u8], max_colors: u16, max_bytes: usize) -> Result<(Vec<u8>, usize), Error> {
    let image = decode(source, max_bytes)?;
    encode_decoded(&image, max_colors)
}

fn encode_decoded(image: &DecodedImage, max_colors: u16) -> Result<(Vec<u8>, usize), Error> {
    let mut map: HashMap<[u16; 4], u8> = HashMap::new();
    let mut colors = Vec::<[u8; 4]>::new();
    let mut indices = Vec::with_capacity(image.rgba16.len());
    for &pixel in &image.rgba16 {
        if pixel.iter().any(|sample| sample % 257 != 0) {
            return Err(Error::ExactPalette(
                "16-bit samples cannot be represented by an 8-bit PNG palette".into(),
            ));
        }
        if let Some(&index) = map.get(&pixel) {
            indices.push(index);
            continue;
        }
        if colors.len() >= usize::from(max_colors) {
            return Err(Error::TooManyColors {
                found_at_least: colors.len() + 1,
                maximum: max_colors,
            });
        }
        let index = colors.len() as u8;
        map.insert(pixel, index);
        colors.push([
            pixel[0] as u8,
            pixel[1] as u8,
            pixel[2] as u8,
            pixel[3] as u8,
        ]);
        indices.push(index);
    }
    let palette: Vec<u8> = colors.iter().flat_map(|c| [c[0], c[1], c[2]]).collect();
    let last_alpha = colors.iter().rposition(|c| c[3] != 255);
    let transparency: Vec<u8> = last_alpha
        .map(|last| colors[..=last].iter().map(|c| c[3]).collect())
        .unwrap_or_default();
    let mut encoded = Vec::new();
    {
        let mut encoder = png::Encoder::new(Cursor::new(&mut encoded), image.width, image.height);
        encoder.set_color(png::ColorType::Indexed);
        encoder.set_depth(png::BitDepth::Eight);
        encoder.set_palette(palette);
        if !transparency.is_empty() {
            encoder.set_trns(transparency);
        }
        let mut writer = encoder.write_header()?;
        writer.write_image_data(&indices)?;
    }
    Ok((encoded, colors.len()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_palette_round_trips_transparency() {
        let image = DecodedImage {
            width: 2,
            height: 1,
            rgba16: vec![[65535, 0, 0, 65535], [0, 65535, 0, 0]],
        };
        let (png, count) = encode_decoded(&image, 2).unwrap();
        assert_eq!(count, 2);
        assert_eq!(decode(&png, 1024).unwrap(), image);
    }

    #[test]
    fn rejects_too_many_colors() {
        let image = DecodedImage {
            width: 3,
            height: 1,
            rgba16: vec![[0, 0, 0, 65535], [257, 0, 0, 65535], [514, 0, 0, 65535]],
        };
        assert!(matches!(
            encode_decoded(&image, 2),
            Err(Error::TooManyColors { .. })
        ));
    }
}
