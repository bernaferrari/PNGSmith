use crate::{
    Error,
    image_data::decode,
    profile::{CanvasOptions, CropOptions},
};
use std::io::Cursor;

pub fn encode(source: &[u8], crop: CropOptions, max_bytes: usize) -> Result<Vec<u8>, Error> {
    let image = decode(source, max_bytes)?;
    let right = crop
        .x
        .checked_add(crop.width)
        .ok_or_else(|| Error::InvalidRequest("crop rectangle overflows".into()))?;
    let bottom = crop
        .y
        .checked_add(crop.height)
        .ok_or_else(|| Error::InvalidRequest("crop rectangle overflows".into()))?;
    if right > image.width || bottom > image.height {
        return Err(Error::InvalidRequest(format!(
            "crop rectangle {}×{} at {},{} exceeds image dimensions {}×{}",
            crop.width, crop.height, crop.x, crop.y, image.width, image.height
        )));
    }

    let source_width = image.width as usize;
    let mut pixels = Vec::with_capacity(crop.width as usize * crop.height as usize);
    for row in crop.y as usize..bottom as usize {
        let start = row * source_width + crop.x as usize;
        let end = start + crop.width as usize;
        pixels.extend_from_slice(&image.rgba16[start..end]);
    }

    // Preserve the source precision. PNG's bit depth byte lives in IHDR after
    // the signature, length, type, width, and height fields.
    let sixteen_bit = source.get(24).is_some_and(|depth| *depth == 16);
    let mut encoded = Vec::new();
    let mut encoder = png::Encoder::new(Cursor::new(&mut encoded), crop.width, crop.height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(if sixteen_bit {
        png::BitDepth::Sixteen
    } else {
        png::BitDepth::Eight
    });
    let mut writer = encoder.write_header()?;
    if sixteen_bit {
        let bytes = pixels
            .iter()
            .flat_map(|pixel| pixel.iter().flat_map(|sample| sample.to_be_bytes()))
            .collect::<Vec<_>>();
        writer.write_image_data(&bytes)?;
    } else {
        let bytes = pixels
            .iter()
            .flat_map(|pixel| pixel.iter().map(|sample| (sample / 257) as u8))
            .collect::<Vec<_>>();
        writer.write_image_data(&bytes)?;
    }
    drop(writer);
    Ok(encoded)
}

pub fn compose(source: &[u8], canvas: CanvasOptions, max_bytes: usize) -> Result<Vec<u8>, Error> {
    if canvas.width == 0 || canvas.height == 0 {
        return Err(Error::InvalidRequest(
            "canvas dimensions must be positive".into(),
        ));
    }
    if !canvas.image_scale.is_finite() || canvas.image_scale <= 0.0 || canvas.image_scale > 16.0 {
        return Err(Error::InvalidRequest(
            "image_scale must be between 0 and 16".into(),
        ));
    }

    let output_bytes = (canvas.width as usize)
        .checked_mul(canvas.height as usize)
        .and_then(|pixels| pixels.checked_mul(std::mem::size_of::<[u16; 4]>()))
        .ok_or_else(|| Error::InvalidRequest("canvas dimensions overflow".into()))?;
    if output_bytes > max_bytes {
        return Err(Error::InvalidRequest(format!(
            "canvas requires {output_bytes} decoded bytes, exceeding the configured limit of {max_bytes}"
        )));
    }

    let image = decode(source, max_bytes)?;
    let source_width = image.width as i32;
    let source_height = image.height as i32;
    let scale = canvas.image_scale;
    let mut pixels = vec![[0u16; 4]; canvas.width as usize * canvas.height as usize];

    if scale < 1.0 {
        let scaled_width = ((f64::from(image.width) * scale).round() as u32).max(1);
        let scaled_height = ((f64::from(image.height) * scale).round() as u32).max(1);
        let scaled = lanczos_resample(
            &image.rgba16,
            image.width,
            image.height,
            scaled_width,
            scaled_height,
        );
        for scaled_y in 0..scaled_height as i32 {
            let output_y = scaled_y + canvas.image_offset_y;
            if output_y < 0 || output_y >= canvas.height as i32 {
                continue;
            }
            for scaled_x in 0..scaled_width as i32 {
                let output_x = scaled_x + canvas.image_offset_x;
                if output_x < 0 || output_x >= canvas.width as i32 {
                    continue;
                }
                pixels[output_y as usize * canvas.width as usize + output_x as usize] =
                    scaled[scaled_y as usize * scaled_width as usize + scaled_x as usize];
            }
        }
        return encode_rgba(source, canvas.width, canvas.height, &pixels);
    }

    for output_y in 0..canvas.height as i32 {
        let source_y = (f64::from(output_y - canvas.image_offset_y) + 0.5) / scale - 0.5;
        if source_y < -0.5 || source_y > f64::from(source_height) - 0.5 {
            continue;
        }
        for output_x in 0..canvas.width as i32 {
            let source_x = (f64::from(output_x - canvas.image_offset_x) + 0.5) / scale - 0.5;
            if source_x < -0.5 || source_x > f64::from(source_width) - 0.5 {
                continue;
            }
            let pixel = bilinear_sample(
                &image.rgba16,
                source_width,
                source_height,
                source_x,
                source_y,
            );
            pixels[output_y as usize * canvas.width as usize + output_x as usize] = pixel;
        }
    }

    encode_rgba(source, canvas.width, canvas.height, &pixels)
}

/// Separable Lanczos-3 downsampling in premultiplied-alpha space. Processing
/// alpha this way prevents transparent edges from developing dark fringes.
fn lanczos_resample(
    pixels: &[[u16; 4]],
    source_width: u32,
    source_height: u32,
    target_width: u32,
    target_height: u32,
) -> Vec<[u16; 4]> {
    let horizontal_weights = resample_weights(source_width, target_width);
    let vertical_weights = resample_weights(source_height, target_height);
    let mut horizontal = vec![[0u16; 4]; target_width as usize * source_height as usize];

    for y in 0..source_height as usize {
        for (target_x, weights) in horizontal_weights.iter().enumerate() {
            let mut accumulated = [0.0f64; 4];
            for &(source_x, weight) in weights {
                let pixel = pixels[y * source_width as usize + source_x];
                let alpha = f64::from(pixel[3]) / 65535.0;
                accumulated[0] += f64::from(pixel[0]) * alpha * weight;
                accumulated[1] += f64::from(pixel[1]) * alpha * weight;
                accumulated[2] += f64::from(pixel[2]) * alpha * weight;
                accumulated[3] += f64::from(pixel[3]) * weight;
            }
            horizontal[y * target_width as usize + target_x] =
                accumulated.map(|value| value.round().clamp(0.0, 65535.0) as u16);
        }
    }

    let mut output = vec![[0u16; 4]; target_width as usize * target_height as usize];
    for (target_y, weights) in vertical_weights.iter().enumerate() {
        for x in 0..target_width as usize {
            let mut accumulated = [0.0f64; 4];
            for &(source_y, weight) in weights {
                let pixel = horizontal[source_y * target_width as usize + x];
                for channel in 0..4 {
                    accumulated[channel] += f64::from(pixel[channel]) * weight;
                }
            }
            let alpha = accumulated[3].round().clamp(0.0, 65535.0);
            let mut result = [0u16; 4];
            result[3] = alpha as u16;
            if alpha > 0.0 {
                let unpremultiply = 65535.0 / alpha;
                for channel in 0..3 {
                    result[channel] = (accumulated[channel] * unpremultiply)
                        .round()
                        .clamp(0.0, 65535.0) as u16;
                }
            }
            output[target_y * target_width as usize + x] = result;
        }
    }
    output
}

fn resample_weights(source_size: u32, target_size: u32) -> Vec<Vec<(usize, f64)>> {
    let scale = f64::from(target_size) / f64::from(source_size);
    let kernel_scale = scale.min(1.0);
    let radius = 3.0 / kernel_scale;
    (0..target_size)
        .map(|target| {
            let center = (f64::from(target) + 0.5) / scale - 0.5;
            let first = (center - radius).floor() as i32;
            let last = (center + radius).ceil() as i32;
            let mut combined = std::collections::BTreeMap::<usize, f64>::new();
            for candidate in first..=last {
                let clamped = candidate.clamp(0, source_size as i32 - 1) as usize;
                let weight = lanczos((center - f64::from(candidate)) * kernel_scale);
                *combined.entry(clamped).or_default() += weight;
            }
            let total: f64 = combined.values().sum();
            combined
                .into_iter()
                .map(|(index, weight)| (index, weight / total))
                .collect()
        })
        .collect()
}

fn lanczos(value: f64) -> f64 {
    let x = value.abs();
    if x < f64::EPSILON {
        1.0
    } else if x >= 3.0 {
        0.0
    } else {
        let pi_x = std::f64::consts::PI * x;
        (pi_x.sin() / pi_x) * ((pi_x / 3.0).sin() / (pi_x / 3.0))
    }
}

fn bilinear_sample(pixels: &[[u16; 4]], width: i32, height: i32, x: f64, y: f64) -> [u16; 4] {
    let x0 = x.floor() as i32;
    let y0 = y.floor() as i32;
    let x1 = x0 + 1;
    let y1 = y0 + 1;
    let fx = x - f64::from(x0);
    let fy = y - f64::from(y0);
    let sample = |sx: i32, sy: i32| -> [u16; 4] {
        if sx < 0 || sy < 0 || sx >= width || sy >= height {
            [0; 4]
        } else {
            pixels[sy as usize * width as usize + sx as usize]
        }
    };
    let a = sample(x0, y0);
    let b = sample(x1, y0);
    let c = sample(x0, y1);
    let d = sample(x1, y1);
    let mut result = [0u16; 4];
    for channel in 0..4 {
        let top = f64::from(a[channel]) * (1.0 - fx) + f64::from(b[channel]) * fx;
        let bottom = f64::from(c[channel]) * (1.0 - fx) + f64::from(d[channel]) * fx;
        result[channel] = (top * (1.0 - fy) + bottom * fy).round().clamp(0.0, 65535.0) as u16;
    }
    result
}

fn encode_rgba(
    source: &[u8],
    width: u32,
    height: u32,
    pixels: &[[u16; 4]],
) -> Result<Vec<u8>, Error> {
    let sixteen_bit = source.get(24).is_some_and(|depth| *depth == 16);
    let mut encoded = Vec::new();
    let mut encoder = png::Encoder::new(Cursor::new(&mut encoded), width, height);
    encoder.set_color(png::ColorType::Rgba);
    encoder.set_depth(if sixteen_bit {
        png::BitDepth::Sixteen
    } else {
        png::BitDepth::Eight
    });
    let mut writer = encoder.write_header()?;
    if sixteen_bit {
        let bytes = pixels
            .iter()
            .flat_map(|pixel| pixel.iter().flat_map(|sample| sample.to_be_bytes()))
            .collect::<Vec<_>>();
        writer.write_image_data(&bytes)?;
    } else {
        let bytes = pixels
            .iter()
            .flat_map(|pixel| pixel.iter().map(|sample| (sample / 257) as u8))
            .collect::<Vec<_>>();
        writer.write_image_data(&bytes)?;
    }
    drop(writer);
    Ok(encoded)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::image_data::decode;
    use std::io::Cursor;

    #[test]
    fn crops_using_top_left_pixel_coordinates() {
        let mut source = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut source), 3, 2);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().unwrap();
        writer
            .write_image_data(&[
                255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 0, 0, 0, 255, 255, 255, 255, 255,
                128, 128, 128, 255,
            ])
            .unwrap();
        drop(writer);

        let output = encode(
            &source,
            CropOptions {
                x: 1,
                y: 0,
                width: 2,
                height: 1,
            },
            1024,
        )
        .unwrap();
        let decoded = decode(&output, 1024).unwrap();
        assert_eq!((decoded.width, decoded.height), (2, 1));
        assert_eq!(decoded.rgba16[0], [0, u16::MAX, 0, u16::MAX]);
        assert_eq!(decoded.rgba16[1], [0, 0, u16::MAX, u16::MAX]);
    }

    #[test]
    fn composes_on_a_transparent_canvas() {
        let mut source = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut source), 2, 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().unwrap();
        writer
            .write_image_data(&[255, 0, 0, 255, 0, 255, 0, 255])
            .unwrap();
        drop(writer);

        let output = compose(
            &source,
            CanvasOptions {
                width: 4,
                height: 2,
                image_scale: 1.0,
                image_offset_x: 1,
                image_offset_y: 1,
            },
            1024,
        )
        .unwrap();
        let decoded = decode(&output, 1024).unwrap();
        assert_eq!((decoded.width, decoded.height), (4, 2));
        assert_eq!(decoded.rgba16[0], [0, 0, 0, 0]);
        assert_eq!(decoded.rgba16[5], [u16::MAX, 0, 0, u16::MAX]);
        assert_eq!(decoded.rgba16[6], [0, u16::MAX, 0, u16::MAX]);
    }

    #[test]
    fn scales_the_image_smaller_than_the_canvas() {
        let mut source = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut source), 2, 2);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().unwrap();
        writer
            .write_image_data(&[
                255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255, 255, 0, 0, 255,
            ])
            .unwrap();
        drop(writer);

        let output = compose(
            &source,
            CanvasOptions {
                width: 4,
                height: 4,
                image_scale: 0.5,
                image_offset_x: 1,
                image_offset_y: 1,
            },
            2048,
        )
        .unwrap();
        let decoded = decode(&output, 2048).unwrap();
        assert_eq!((decoded.width, decoded.height), (4, 4));
        assert_eq!(decoded.rgba16[0][3], 0);
        assert_eq!(decoded.rgba16[5], [u16::MAX, 0, 0, u16::MAX]);
        assert_eq!(decoded.rgba16[15][3], 0);
    }

    #[test]
    fn downsampling_does_not_bleed_hidden_transparent_colors() {
        let source = [[u16::MAX, 0, 0, u16::MAX], [0, 0, u16::MAX, 0]];
        let output = lanczos_resample(&source, 2, 1, 1, 1);
        assert!(output[0][3] > 20_000 && output[0][3] < 50_000);
        assert!(output[0][0] > 60_000);
        assert!(output[0][2] < 100);
    }
}
