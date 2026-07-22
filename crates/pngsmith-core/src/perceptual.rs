#[cfg(feature = "perceptual")]
use crate::image_data::{DecodedImage, decode};
use crate::{Error, profile::AutoColorStrategy, profile::PerceptualOptions};
#[cfg(feature = "perceptual")]
use std::io::Cursor;

#[derive(Debug)]
pub struct AutomaticResult {
    pub bytes: Vec<u8>,
    pub palette_entries: usize,
    pub color_budget: u16,
}

#[cfg(feature = "perceptual")]
pub fn encode(
    source: &[u8],
    max_colors: u16,
    max_bytes: usize,
    config: &PerceptualOptions,
) -> Result<(Vec<u8>, usize), Error> {
    let image = decode(source, max_bytes)?;
    let pixels = rgba8(&image);
    encode_decoded(&image, &pixels, max_colors, config)
}

#[cfg(feature = "perceptual")]
pub fn encode_automatic(
    source: &[u8],
    max_colors: u16,
    max_bytes: usize,
    strategy: AutoColorStrategy,
) -> Result<AutomaticResult, Error> {
    let image = decode(source, max_bytes)?;
    let pixels = rgba8(&image);
    let quality = PerceptualOptions {
        quality_min: strategy.minimum_quality(),
        quality_max: 100,
    };
    let mut lower_bound = 2;
    let mut upper_bound = max_colors;
    let mut best: Option<AutomaticResult> = None;

    while lower_bound <= upper_bound {
        let candidate = lower_bound + (upper_bound - lower_bound) / 2;
        match encode_decoded(&image, &pixels, candidate, &quality) {
            Ok((bytes, palette_entries)) => {
                best = Some(AutomaticResult {
                    bytes,
                    palette_entries,
                    color_budget: candidate,
                });
                if candidate == 2 {
                    break;
                }
                upper_bound = candidate - 1;
            }
            Err(Error::ImageQuant(imagequant::Error::QualityTooLow)) => {
                lower_bound = candidate + 1;
            }
            Err(error) => return Err(error),
        }
    }

    if let Some(best) = best {
        return Ok(best);
    }

    // Match the app's existing behavior: if even the full palette misses the
    // strategy's quality floor, still produce a 256-color candidate instead of
    // turning Auto into an unexpected lossless fallback.
    let unrestricted = PerceptualOptions {
        quality_min: 0,
        quality_max: 100,
    };
    let (bytes, palette_entries) = encode_decoded(&image, &pixels, max_colors, &unrestricted)?;
    Ok(AutomaticResult {
        bytes,
        palette_entries,
        color_budget: max_colors,
    })
}

#[cfg(feature = "perceptual")]
fn rgba8(image: &DecodedImage) -> Vec<imagequant::RGBA> {
    let pixels: Vec<imagequant::RGBA> = image
        .rgba16
        .iter()
        .map(|p| imagequant::RGBA {
            r: (p[0] / 257) as u8,
            g: (p[1] / 257) as u8,
            b: (p[2] / 257) as u8,
            a: (p[3] / 257) as u8,
        })
        .collect();
    pixels
}

#[cfg(feature = "perceptual")]
fn encode_decoded(
    image: &DecodedImage,
    pixels: &[imagequant::RGBA],
    max_colors: u16,
    config: &PerceptualOptions,
) -> Result<(Vec<u8>, usize), Error> {
    let mut attributes = imagequant::new();
    attributes.set_max_colors(max_colors as u32)?;
    attributes.set_quality(config.quality_min, config.quality_max)?;
    let mut quant_image = attributes.new_image(
        pixels.to_vec(),
        image.width as usize,
        image.height as usize,
        0.0,
    )?;
    let mut result = attributes.quantize(&mut quant_image)?;
    result.set_dithering_level(1.0)?;
    let (palette, indices) = result.remapped(&mut quant_image)?;
    let rgb: Vec<u8> = palette.iter().flat_map(|c| [c.r, c.g, c.b]).collect();
    let last_alpha = palette.iter().rposition(|c| c.a != 255);
    let alpha: Vec<u8> = last_alpha
        .map(|last| palette[..=last].iter().map(|c| c.a).collect())
        .unwrap_or_default();
    let mut encoded = Vec::new();
    {
        let mut encoder = png::Encoder::new(Cursor::new(&mut encoded), image.width, image.height);
        encoder.set_color(png::ColorType::Indexed);
        encoder.set_depth(png::BitDepth::Eight);
        encoder.set_palette(rgb);
        if !alpha.is_empty() {
            encoder.set_trns(alpha);
        }
        let mut writer = encoder.write_header()?;
        writer.write_image_data(&indices)?;
    }
    Ok((encoded, palette.len()))
}

#[cfg(not(feature = "perceptual"))]
pub fn encode(
    _source: &[u8],
    _max_colors: u16,
    _max_bytes: usize,
    _config: &PerceptualOptions,
) -> Result<(Vec<u8>, usize), Error> {
    Err(Error::Perceptual(
        "this build does not include perceptual quantization".into(),
    ))
}

#[cfg(not(feature = "perceptual"))]
pub fn encode_automatic(
    _source: &[u8],
    _max_colors: u16,
    _max_bytes: usize,
    _strategy: AutoColorStrategy,
) -> Result<AutomaticResult, Error> {
    Err(Error::Perceptual(
        "this build does not include perceptual quantization".into(),
    ))
}
