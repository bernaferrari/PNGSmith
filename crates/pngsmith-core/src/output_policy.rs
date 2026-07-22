use crate::profile::Request;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WriteDecision {
    Write,
    SkipNotSmaller,
}

pub fn decide(request: &Request, source_bytes: usize, output_bytes: usize) -> WriteDecision {
    let is_image_edit = request.crop.is_some() || request.canvas.is_some();
    if request.output.only_if_smaller && !is_image_edit && output_bytes >= source_bytes {
        WriteDecision::SkipNotSmaller
    } else {
        WriteDecision::Write
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::profile::{CanvasOptions, OutputOptions};

    #[test]
    fn image_edits_are_never_discarded_by_compression_policy() {
        let request = Request {
            canvas: Some(CanvasOptions {
                width: 2,
                height: 2,
                image_scale: 1.0,
                image_offset_x: 0,
                image_offset_y: 0,
            }),
            output: OutputOptions {
                only_if_smaller: true,
                ..OutputOptions::default()
            },
            ..Request::default()
        };
        assert_eq!(decide(&request, 100, 120), WriteDecision::Write);
    }

    #[test]
    fn pure_compression_can_still_skip_larger_results() {
        let request = Request {
            output: OutputOptions {
                only_if_smaller: true,
                ..OutputOptions::default()
            },
            ..Request::default()
        };
        assert_eq!(decide(&request, 100, 120), WriteDecision::SkipNotSmaller);
    }
}
