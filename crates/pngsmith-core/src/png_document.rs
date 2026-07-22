use crate::Error;
use std::io::Cursor;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AnimationInfo {
    pub frame_count: u32,
    pub play_count: u32,
    pub has_separate_default_image: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DocumentInfo {
    pub animation: Option<AnimationInfo>,
}

impl DocumentInfo {
    pub fn is_animated(self) -> bool {
        self.animation.is_some()
    }
}

pub fn inspect(source: &[u8], max_bytes: usize) -> Result<DocumentInfo, Error> {
    let mut decoder = png::Decoder::new(Cursor::new(source));
    decoder.set_limits(png::Limits { bytes: max_bytes });
    let reader = decoder.read_info()?;
    let animation = reader
        .info()
        .animation_control
        .map(|control| AnimationInfo {
            frame_count: control.num_frames,
            play_count: control.num_plays,
            has_separate_default_image: reader.info().frame_control.is_none(),
        });
    Ok(DocumentInfo { animation })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn distinguishes_still_and_animated_pngs() {
        let mut still = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut still, 1, 1);
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            encoder
                .write_header()
                .unwrap()
                .write_image_data(&[0, 0, 0, 255])
                .unwrap();
        }
        assert!(!inspect(&still, 1024).unwrap().is_animated());

        let mut animated = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut animated, 1, 1);
            encoder.set_color(png::ColorType::Rgba);
            encoder.set_depth(png::BitDepth::Eight);
            encoder.set_animated(2, 0).unwrap();
            let mut writer = encoder.write_header().unwrap();
            writer.write_image_data(&[0, 0, 0, 255]).unwrap();
            writer.write_image_data(&[255, 255, 255, 255]).unwrap();
        }
        assert_eq!(
            inspect(&animated, 1024).unwrap().animation,
            Some(AnimationInfo {
                frame_count: 2,
                play_count: 0,
                has_separate_default_image: false,
            })
        );
    }
}
