use crate::image_data::DecodedImage;
use std::collections::HashSet;

/// The highest source-color count worth retaining for preview diagnostics.
/// Palette output is limited to 256 colors, so values above this threshold are
/// reported as a bounded lower result instead of growing memory with the image.
pub const LIMIT: usize = 10_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SourceColorCount {
    Exact(usize),
    MoreThan(usize),
}

impl SourceColorCount {
    pub fn response_values(self) -> (Option<usize>, Option<usize>) {
        match self {
            Self::Exact(count) => (Some(count), None),
            Self::MoreThan(limit) => (None, Some(limit)),
        }
    }
}

/// Counts the same 8-bit RGBA values consumed by palette reduction while
/// retaining no more than `LIMIT` packed colors.
pub fn count(image: &DecodedImage) -> SourceColorCount {
    let mut colors = HashSet::with_capacity(image.rgba16.len().min(256));
    for &pixel in &image.rgba16 {
        let color = rgba8_key(pixel);
        if colors.len() < LIMIT {
            colors.insert(color);
        } else if !colors.contains(&color) {
            return SourceColorCount::MoreThan(LIMIT);
        }
    }
    SourceColorCount::Exact(colors.len())
}

fn rgba8_key(pixel: [u16; 4]) -> u32 {
    u32::from_be_bytes(pixel.map(|sample| (sample / 257) as u8))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn image(pixels: Vec<[u16; 4]>) -> DecodedImage {
        DecodedImage {
            width: pixels.len() as u32,
            height: 1,
            rgba16: pixels,
        }
    }

    #[test]
    fn reports_exact_color_counts_at_or_below_the_limit() {
        let pixels = vec![
            [0, 0, 0, u16::MAX],
            [0, 0, 0, u16::MAX],
            [u16::MAX, 0, 0, u16::MAX],
        ];
        assert_eq!(count(&image(pixels)), SourceColorCount::Exact(2));

        let pixels = (0..LIMIT)
            .map(|value| {
                let [_, red, green, blue] = (value as u32).to_be_bytes();
                [
                    u16::from(red) * 257,
                    u16::from(green) * 257,
                    u16::from(blue) * 257,
                    u16::MAX,
                ]
            })
            .collect();
        assert_eq!(count(&image(pixels)), SourceColorCount::Exact(LIMIT));
    }

    #[test]
    fn stops_at_the_limit_when_another_color_is_found() {
        let pixels = (0..=LIMIT)
            .map(|value| {
                let [_, red, green, blue] = (value as u32).to_be_bytes();
                [
                    u16::from(red) * 257,
                    u16::from(green) * 257,
                    u16::from(blue) * 257,
                    u16::MAX,
                ]
            })
            .collect();
        assert_eq!(count(&image(pixels)), SourceColorCount::MoreThan(LIMIT));
    }

    #[test]
    fn counts_the_same_eight_bit_colors_used_by_palette_reduction() {
        let pixels = vec![
            [256, 0, 0, u16::MAX],
            [0, 0, 0, u16::MAX],
            [257, 0, 0, u16::MAX],
        ];
        assert_eq!(count(&image(pixels)), SourceColorCount::Exact(2));
    }
}
