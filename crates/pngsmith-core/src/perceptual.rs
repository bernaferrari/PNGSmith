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
struct EncodedPalette {
    bytes: Vec<u8>,
    palette_entries: usize,
    quality: u8,
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
    let encoded = encode_decoded(&image, &pixels, max_colors, config)?;
    Ok((encoded.bytes, encoded.palette_entries))
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
    let unrestricted = PerceptualOptions {
        quality_min: 0,
        quality_max: 100,
    };

    // Some continuous-tone images cannot reach the nominal quality floor even
    // with all 256 palette entries. The previous fallback returned that same
    // unrestricted 256-color result for both strategies, making Smaller
    // indistinguishable from Balanced. Anchor the search to the best quality
    // this particular image can achieve, then preserve a meaningful quality
    // gap between the strategies when the nominal floors are unreachable.
    let maximum = encode_decoded(&image, &pixels, max_colors, &unrestricted)?;
    let quality_floor = effective_quality_floor(strategy, maximum.quality);
    let mut lower_bound = 2;
    let mut upper_bound = max_colors.saturating_sub(1);
    let mut best = AutomaticResult {
        bytes: maximum.bytes,
        palette_entries: maximum.palette_entries,
        color_budget: max_colors,
    };

    while lower_bound <= upper_bound {
        let candidate = lower_bound + (upper_bound - lower_bound) / 2;
        let encoded = encode_decoded(&image, &pixels, candidate, &unrestricted)?;
        if encoded.quality >= quality_floor {
            best = AutomaticResult {
                bytes: encoded.bytes,
                palette_entries: encoded.palette_entries,
                color_budget: candidate,
            };
            if candidate == 2 {
                break;
            }
            upper_bound = candidate - 1;
        } else {
            lower_bound = candidate + 1;
        }
    }

    Ok(best)
}

#[cfg(feature = "perceptual")]
fn effective_quality_floor(strategy: AutoColorStrategy, maximum_quality: u8) -> u8 {
    match strategy {
        AutoColorStrategy::Balanced => strategy.minimum_quality().min(maximum_quality),
        AutoColorStrategy::Smaller => strategy
            .minimum_quality()
            .min(maximum_quality.saturating_sub(8)),
    }
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
) -> Result<EncodedPalette, Error> {
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
    let quality = result.quantization_quality().unwrap_or(100);
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
    Ok(EncodedPalette {
        bytes: encoded,
        palette_entries: palette.len(),
        quality,
    })
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
