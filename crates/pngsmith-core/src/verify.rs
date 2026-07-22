use crate::{Error, image_data::decode, png_document};
use std::io::Cursor;

pub fn decoded_pixels(source: &[u8], output: &[u8], max_bytes: usize) -> Result<bool, Error> {
    let source_document = png_document::inspect(source, max_bytes)?;
    let output_document = png_document::inspect(output, max_bytes)?;
    if source_document.animation != output_document.animation {
        return Ok(false);
    }
    if source_document.is_animated() {
        return animated_frames_equal(source, output, max_bytes);
    }
    Ok(decode(source, max_bytes)? == decode(output, max_bytes)?)
}

fn animated_frames_equal(source: &[u8], output: &[u8], max_bytes: usize) -> Result<bool, Error> {
    let mut source_decoder = png::Decoder::new(Cursor::new(source));
    source_decoder.set_transformations(png::Transformations::EXPAND);
    source_decoder.set_limits(png::Limits { bytes: max_bytes });
    let mut source_reader = source_decoder.read_info()?;

    let mut output_decoder = png::Decoder::new(Cursor::new(output));
    output_decoder.set_transformations(png::Transformations::EXPAND);
    output_decoder.set_limits(png::Limits { bytes: max_bytes });
    let mut output_reader = output_decoder.read_info()?;

    let animation = png_document::inspect(source, max_bytes)?
        .animation
        .expect("animated_frames_equal requires an animated PNG");
    let frame_reads =
        animation.frame_count as usize + usize::from(animation.has_separate_default_image);

    for _ in 0..frame_reads {
        let mut source_frame = vec![
            0;
            source_reader.output_buffer_size().ok_or_else(|| {
                Error::Decode("animated source frame is too large".into())
            })?
        ];
        let mut output_frame = vec![
            0;
            output_reader.output_buffer_size().ok_or_else(|| {
                Error::Decode("animated output frame is too large".into())
            })?
        ];
        let source_info = source_reader.next_frame(&mut source_frame)?;
        let output_info = output_reader.next_frame(&mut output_frame)?;
        if source_info != output_info
            || source_frame[..source_info.buffer_size()]
                != output_frame[..output_info.buffer_size()]
            || frame_control(source_reader.info().frame_control.as_ref())
                != frame_control(output_reader.info().frame_control.as_ref())
        {
            return Ok(false);
        }
    }
    Ok(true)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct FrameControl {
    width: u32,
    height: u32,
    x_offset: u32,
    y_offset: u32,
    delay_num: u16,
    delay_den: u16,
    dispose_op: png::DisposeOp,
    blend_op: png::BlendOp,
}

fn frame_control(control: Option<&png::FrameControl>) -> Option<FrameControl> {
    control.map(|control| FrameControl {
        width: control.width,
        height: control.height,
        x_offset: control.x_offset,
        y_offset: control.y_offset,
        delay_num: control.delay_num,
        delay_den: control.delay_den,
        dispose_op: control.dispose_op,
        blend_op: control.blend_op,
    })
}
