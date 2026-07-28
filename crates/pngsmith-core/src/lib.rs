mod crop;
mod exact_palette;
mod image_data;
mod lossless;
mod metadata;
mod output;
mod output_policy;
mod perceptual;
mod png_document;
pub mod profile;
mod source_color_count;
mod verify;

pub use profile::{
    AutoColorStrategy, AutomaticOptions, CanvasOptions, CompressionMode, CropOptions, Fallback,
    LosslessOptions, MetadataPolicy, OutputOptions, PerceptualOptions, Request, VerifyOptions,
    builtin_profile,
};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    path::{Path, PathBuf},
};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid PNG: {0}")]
    PngDecode(#[from] png::DecodingError),
    #[error("could not encode PNG: {0}")]
    PngEncode(#[from] png::EncodingError),
    #[error("OxiPNG failed: {0}")]
    OxiPng(#[from] oxipng::PngError),
    #[cfg(feature = "perceptual")]
    #[error("imagequant failed: {0}")]
    ImageQuant(#[from] imagequant::Error),
    #[error("could not decode image: {0}")]
    Decode(String),
    #[error("exact palette conversion failed: {0}")]
    ExactPalette(String),
    #[error(
        "image needs at least {found_at_least} colors, exceeding the configured maximum of {maximum}"
    )]
    TooManyColors { found_at_least: usize, maximum: u16 },
    #[error("perceptual conversion failed: {0}")]
    Perceptual(String),
    #[error("verification failed: {0}")]
    Verification(String),
    #[error("could not write output: {0}")]
    Output(String),
    #[error("invalid request: {0}")]
    InvalidRequest(String),
    #[error("JSON error: {0}")]
    Json(#[from] serde_json::Error),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Response {
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    pub results: Vec<FileResult>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileResult {
    pub input: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub original_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub output_bytes: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub actual_mode: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub palette_entries: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub color_budget: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_colors: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source_colors_at_least: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub pixel_identical: Option<bool>,
    pub lossy: bool,
    pub written: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub skipped_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

struct Candidate {
    bytes: Vec<u8>,
    mode: &'static str,
    palette_entries: Option<usize>,
    color_budget: Option<u16>,
    source_colors: Option<usize>,
    source_colors_at_least: Option<usize>,
    lossy: bool,
    optimized: bool,
}

pub fn execute(request: &Request) -> Response {
    if let Err(error) = request.validate() {
        return Response {
            ok: false,
            error: Some(error),
            results: Vec::new(),
        };
    }
    let results: Vec<_> = request
        .inputs
        .iter()
        .map(|input| {
            process_file(Path::new(input), request).unwrap_or_else(|error| FileResult {
                input: input.clone(),
                output: None,
                original_bytes: None,
                output_bytes: None,
                actual_mode: None,
                palette_entries: None,
                color_budget: None,
                source_colors: None,
                source_colors_at_least: None,
                pixel_identical: None,
                lossy: false,
                written: false,
                skipped_reason: None,
                error: Some(error.to_string()),
            })
        })
        .collect();
    let failures = results.iter().filter(|r| r.error.is_some()).count();
    Response {
        ok: failures == 0,
        error: (failures > 0).then(|| format!("{failures} of {} files failed", results.len())),
        results,
    }
}

pub fn execute_json(request_json: &str) -> Result<String, Error> {
    let request: Request = serde_json::from_str(request_json)?;
    Ok(serde_json::to_string(&execute(&request))?)
}

fn process_file(input: &Path, request: &Request) -> Result<FileResult, Error> {
    ensure_png_path(input)?;
    let source = fs::read(input)?;
    if source.len() < 8 || &source[..8] != b"\x89PNG\r\n\x1a\n" {
        return Err(Error::InvalidRequest(format!(
            "{} is not a PNG file",
            input.display()
        )));
    }
    let document = png_document::inspect(&source, request.lossless.max_decompressed_bytes)?;
    if document.is_animated() && (request.canvas.is_some() || request.crop.is_some()) {
        return Err(Error::InvalidRequest(
            "cropping animated PNGs is not supported; save the animation without cropping".into(),
        ));
    }
    let working_source = if let Some(canvas) = request.canvas {
        let composed = crop::compose(&source, canvas, request.lossless.max_decompressed_bytes)?;
        if request.lossless.effective_metadata() == MetadataPolicy::StripAll {
            composed
        } else {
            metadata::copy_compatible_chunks(&source, &composed)?
        }
    } else if let Some(crop) = request.crop {
        let cropped = crop::encode(&source, crop, request.lossless.max_decompressed_bytes)?;
        if request.lossless.effective_metadata() == MetadataPolicy::StripAll {
            cropped
        } else {
            metadata::copy_compatible_chunks(&source, &cropped)?
        }
    } else {
        source.clone()
    };
    let mut candidate = make_candidate(&working_source, request, document)?;
    if candidate.palette_entries.is_some()
        && !candidate.optimized
        && request.lossless.effective_metadata() == MetadataPolicy::Preserve
    {
        candidate.bytes = metadata::copy_compatible_chunks(&working_source, &candidate.bytes)?;
    }
    if !candidate.optimized {
        candidate.bytes = lossless::optimize(&candidate.bytes, &request.lossless)?;
    }
    let pixel_identical = if request.verify.decoded_pixels && !candidate.lossy {
        let identical = verify::decoded_pixels(
            &working_source,
            &candidate.bytes,
            request.lossless.max_decompressed_bytes,
        )?;
        if !identical {
            return Err(Error::Verification(
                "decoded pixels changed during lossless compression".into(),
            ));
        }
        Some(true)
    } else {
        None
    };
    let destination =
        output::destination(input, request.output.create_copy, &request.output.suffix)?;
    let write_decision = output_policy::decide(request, source.len(), candidate.bytes.len());
    let written = write_decision == output_policy::WriteDecision::Write;
    if written {
        output::atomic_write(&destination, &candidate.bytes, input)?;
    }
    Ok(FileResult {
        input: path_string(input),
        output: written.then(|| path_string(&destination)),
        original_bytes: Some(source.len() as u64),
        output_bytes: Some(candidate.bytes.len() as u64),
        actual_mode: Some(candidate.mode.into()),
        palette_entries: candidate.palette_entries,
        color_budget: candidate.color_budget,
        source_colors: candidate.source_colors,
        source_colors_at_least: candidate.source_colors_at_least,
        pixel_identical,
        lossy: candidate.lossy,
        written,
        skipped_reason: (!written).then(|| "optimized result was not smaller".into()),
        error: None,
    })
}

fn make_candidate(
    source: &[u8],
    request: &Request,
    document: png_document::DocumentInfo,
) -> Result<Candidate, Error> {
    let max = request.max_colors.unwrap_or(256);
    match request.mode {
        CompressionMode::Lossless => Ok(Candidate {
            bytes: source.to_vec(),
            mode: "lossless",
            palette_entries: None,
            color_budget: None,
            source_colors: None,
            source_colors_at_least: None,
            lossy: false,
            optimized: false,
        }),
        CompressionMode::ExactPalette => {
            if document.is_animated() {
                return animated_palette_fallback(source, request);
            }
            match exact_palette::encode(source, max, request.lossless.max_decompressed_bytes) {
                Ok((bytes, count)) => Ok(Candidate {
                    bytes,
                    mode: "exact_palette",
                    palette_entries: Some(count),
                    color_budget: None,
                    source_colors: Some(count),
                    source_colors_at_least: None,
                    lossy: false,
                    optimized: false,
                }),
                Err(Error::TooManyColors { .. } | Error::ExactPalette(_))
                    if request.fallback == Fallback::Lossless =>
                {
                    Ok(Candidate {
                        bytes: source.to_vec(),
                        mode: "lossless_fallback",
                        palette_entries: None,
                        color_budget: None,
                        source_colors: None,
                        source_colors_at_least: None,
                        lossy: false,
                        optimized: false,
                    })
                }
                Err(error) => Err(error),
            }
        }
        CompressionMode::SmartLossless => {
            let lossless = lossless::optimize(source, &request.lossless)?;
            if document.is_animated() {
                return Ok(Candidate {
                    bytes: lossless,
                    mode: "lossless",
                    palette_entries: None,
                    color_budget: None,
                    source_colors: None,
                    source_colors_at_least: None,
                    lossy: false,
                    optimized: true,
                });
            }
            match exact_palette::encode(source, max, request.lossless.max_decompressed_bytes) {
                Ok((palette, count)) => {
                    let palette =
                        if request.lossless.effective_metadata() == MetadataPolicy::Preserve {
                            metadata::copy_compatible_chunks(source, &palette)?
                        } else {
                            palette
                        };
                    let palette = lossless::optimize(&palette, &request.lossless)?;
                    if palette.len() < lossless.len() {
                        Ok(Candidate {
                            bytes: palette,
                            mode: "exact_palette",
                            palette_entries: Some(count),
                            color_budget: None,
                            source_colors: Some(count),
                            source_colors_at_least: None,
                            lossy: false,
                            optimized: true,
                        })
                    } else {
                        Ok(Candidate {
                            bytes: lossless,
                            mode: "lossless",
                            palette_entries: None,
                            color_budget: None,
                            source_colors: None,
                            source_colors_at_least: None,
                            lossy: false,
                            optimized: true,
                        })
                    }
                }
                Err(Error::TooManyColors { .. } | Error::ExactPalette(_)) => Ok(Candidate {
                    bytes: lossless,
                    mode: "lossless",
                    palette_entries: None,
                    color_budget: None,
                    source_colors: None,
                    source_colors_at_least: None,
                    lossy: false,
                    optimized: true,
                }),
                Err(error) => Err(error),
            }
        }
        CompressionMode::Perceptual => {
            if document.is_animated() {
                return animated_palette_fallback(source, request);
            }
            let image = image_data::decode(source, request.lossless.max_decompressed_bytes)?;
            let (source_colors, source_colors_at_least) =
                source_color_count::count(&image).response_values();
            let (bytes, count) = perceptual::encode_decoded(&image, max, &request.perceptual)?;
            Ok(Candidate {
                bytes,
                mode: "perceptual",
                palette_entries: Some(count),
                color_budget: None,
                source_colors,
                source_colors_at_least,
                lossy: true,
                optimized: false,
            })
        }
        CompressionMode::AutomaticPalette => {
            if document.is_animated() {
                return animated_palette_fallback(source, request);
            }
            let image = image_data::decode(source, request.lossless.max_decompressed_bytes)?;
            let (source_colors, source_colors_at_least) =
                source_color_count::count(&image).response_values();
            if request.automatic.protect_existing_palette
                && source_colors.is_some_and(|count| count <= usize::from(max))
            {
                let mut lossless_request = request.clone();
                lossless_request.mode = CompressionMode::SmartLossless;
                let mut candidate = make_candidate(source, &lossless_request, document)?;
                candidate.source_colors = source_colors;
                candidate.source_colors_at_least = None;
                return Ok(candidate);
            }
            let automatic =
                perceptual::encode_automatic_decoded(&image, max, request.automatic.strategy)?;
            Ok(Candidate {
                bytes: automatic.bytes,
                mode: "automatic_palette",
                palette_entries: Some(automatic.palette_entries),
                color_budget: Some(automatic.color_budget),
                source_colors,
                source_colors_at_least,
                lossy: true,
                optimized: false,
            })
        }
    }
}

fn animated_palette_fallback(source: &[u8], request: &Request) -> Result<Candidate, Error> {
    if request.fallback != Fallback::Lossless {
        return Err(Error::InvalidRequest(
            "color reduction is not supported for animated PNGs; choose lossless compression"
                .into(),
        ));
    }
    Ok(Candidate {
        bytes: source.to_vec(),
        mode: "lossless_fallback",
        palette_entries: None,
        color_budget: None,
        source_colors: None,
        source_colors_at_least: None,
        lossy: false,
        optimized: false,
    })
}

fn ensure_png_path(input: &Path) -> Result<(), Error> {
    if !input.is_file() {
        return Err(Error::InvalidRequest(format!(
            "{} is not a file",
            input.display()
        )));
    }
    if input
        .extension()
        .and_then(|s| s.to_str())
        .is_none_or(|s| !s.eq_ignore_ascii_case("png"))
    {
        return Err(Error::InvalidRequest(format!(
            "{} does not have a .png extension",
            input.display()
        )));
    }
    Ok(())
}

fn path_string(path: &Path) -> String {
    path.canonicalize()
        .unwrap_or_else(|_| PathBuf::from(path))
        .to_string_lossy()
        .into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    fn fixture() -> Vec<u8> {
        let mut data = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut data), 2, 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        encoder
            .add_text_chunk("Author".into(), "PNG Smith".into())
            .unwrap();
        let mut writer = encoder.write_header().unwrap();
        writer
            .write_image_data(&[255, 0, 0, 255, 0, 0, 0, 0])
            .unwrap();
        drop(writer);
        data
    }

    fn animated_fixture() -> Vec<u8> {
        let mut data = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut data), 2, 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        encoder.set_animated(2, 0).unwrap();
        let mut writer = encoder.write_header().unwrap();
        writer
            .write_image_data(&[255, 0, 0, 255, 0, 0, 0, 0])
            .unwrap();
        writer
            .write_image_data(&[0, 255, 0, 255, 0, 0, 0, 0])
            .unwrap();
        drop(writer);
        data
    }

    fn gradient_fixture() -> Vec<u8> {
        let mut data = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut data), 256, 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let pixels: Vec<u8> = (0..=255)
            .flat_map(|value| [value, 255 - value, value / 2, 255])
            .collect();
        encoder
            .write_header()
            .unwrap()
            .write_image_data(&pixels)
            .unwrap();
        data
    }

    fn color_count_fixture(color_count: u16) -> Vec<u8> {
        let mut data = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut data), u32::from(color_count), 1);
        encoder.set_color(png::ColorType::Rgba);
        encoder.set_depth(png::BitDepth::Eight);
        let pixels: Vec<u8> = (0..color_count)
            .flat_map(|value| {
                [
                    (value % 256) as u8,
                    (value / 256) as u8,
                    (value % 251) as u8,
                    255,
                ]
            })
            .collect();
        encoder
            .write_header()
            .unwrap()
            .write_image_data(&pixels)
            .unwrap();
        data
    }

    #[test]
    fn json_contract_processes_a_file() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("sample.png");
        fs::write(&input, fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::ExactPalette,
            fallback: Fallback::Error,
            ..Request::default()
        };
        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        assert_eq!(response.results[0].palette_entries, Some(2));
        assert_eq!(response.results[0].pixel_identical, Some(true));
        assert!(
            response.results[0]
                .output
                .as_ref()
                .is_some_and(|p| Path::new(p).exists())
        );
    }

    #[test]
    fn exact_mode_can_fall_back_without_becoming_lossy() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("fallback.png");
        fs::write(&input, fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::ExactPalette,
            max_colors: Some(2),
            fallback: Fallback::Lossless,
            ..Request::default()
        };
        let mut source = Vec::new();
        let mut encoder = png::Encoder::new(Cursor::new(&mut source), 3, 1);
        encoder.set_color(png::ColorType::Rgb);
        encoder.set_depth(png::BitDepth::Eight);
        let mut writer = encoder.write_header().unwrap();
        writer
            .write_image_data(&[255, 0, 0, 0, 255, 0, 0, 0, 255])
            .unwrap();
        drop(writer);
        fs::write(&input, source).unwrap();
        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        assert_eq!(
            response.results[0].actual_mode.as_deref(),
            Some("lossless_fallback")
        );
        assert!(!response.results[0].lossy);
        assert_eq!(response.results[0].pixel_identical, Some(true));
    }

    #[cfg(feature = "perceptual")]
    #[test]
    fn perceptual_mode_is_explicitly_marked_lossy() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("lossy.png");
        fs::write(&input, fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::Perceptual,
            max_colors: Some(2),
            ..Request::default()
        };
        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        assert!(response.results[0].lossy);
        assert_eq!(response.results[0].pixel_identical, None);
        assert_eq!(response.results[0].source_colors, Some(2));
        assert_eq!(response.results[0].source_colors_at_least, None);
    }

    #[test]
    fn request_crops_before_lossless_compression() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("crop.png");
        fs::write(&input, fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            crop: Some(CropOptions {
                x: 1,
                y: 0,
                width: 1,
                height: 1,
            }),
            mode: CompressionMode::Lossless,
            ..Request::default()
        };
        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        let output = response.results[0].output.as_ref().unwrap();
        let decoded = image_data::decode(&fs::read(output).unwrap(), 1024).unwrap();
        assert_eq!((decoded.width, decoded.height), (1, 1));
        assert_eq!(decoded.rgba16[0], [0, 0, 0, 0]);
        assert_eq!(response.results[0].pixel_identical, Some(true));
        let output_bytes = fs::read(output).unwrap();
        let decoder = png::Decoder::new(Cursor::new(output_bytes));
        let reader = decoder.read_info().unwrap();
        assert!(
            reader
                .info()
                .uncompressed_latin1_text
                .iter()
                .any(|chunk| { chunk.keyword == "Author" && chunk.text == "PNG Smith" })
        );
    }

    #[test]
    fn smart_lossless_preserves_animated_pngs() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("animated.png");
        fs::write(&input, animated_fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::SmartLossless,
            ..Request::default()
        };

        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        assert_eq!(response.results[0].actual_mode.as_deref(), Some("lossless"));
        assert_eq!(response.results[0].pixel_identical, Some(true));
        let output = fs::read(response.results[0].output.as_ref().unwrap()).unwrap();
        assert!(png_document::inspect(&output, 1024).unwrap().is_animated());
    }

    #[cfg(feature = "perceptual")]
    #[test]
    fn automatic_palette_search_is_shared_and_reports_its_budget() {
        assert_eq!(AutoColorStrategy::Balanced.minimum_quality(), 88);
        assert_eq!(AutoColorStrategy::Smaller.minimum_quality(), 74);

        let source = gradient_fixture();
        let image = image_data::decode(&source, 1024 * 1024).unwrap();
        let balanced =
            perceptual::encode_automatic_decoded(&image, 256, AutoColorStrategy::Balanced).unwrap();
        let smaller =
            perceptual::encode_automatic_decoded(&image, 256, AutoColorStrategy::Smaller).unwrap();

        assert!((2..=256).contains(&balanced.color_budget));
        assert!(balanced.palette_entries <= usize::from(balanced.color_budget));
        assert!(
            smaller.color_budget < balanced.color_budget,
            "Smaller should choose a stricter budget than Balanced: {smaller:?} vs {balanced:?}"
        );
    }

    #[cfg(feature = "perceptual")]
    #[test]
    fn automatic_palette_is_available_through_the_request_contract() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("automatic.png");
        fs::write(&input, gradient_fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::AutomaticPalette,
            automatic: AutomaticOptions {
                strategy: AutoColorStrategy::Smaller,
                protect_existing_palette: false,
            },
            ..Request::default()
        };

        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        let result = &response.results[0];
        assert_eq!(result.actual_mode.as_deref(), Some("automatic_palette"));
        assert!(
            result
                .color_budget
                .is_some_and(|budget| (2..=256).contains(&budget))
        );
        assert!(result.lossy);
    }

    #[cfg(feature = "perceptual")]
    #[test]
    fn automatic_palette_caps_reported_source_colors_at_ten_thousand() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("many-colors.png");
        fs::write(
            &input,
            color_count_fixture(source_color_count::LIMIT as u16 + 1),
        )
        .unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::AutomaticPalette,
            automatic: AutomaticOptions {
                strategy: AutoColorStrategy::Balanced,
                protect_existing_palette: false,
            },
            ..Request::default()
        };

        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        let result = &response.results[0];
        assert_eq!(result.source_colors, None);
        assert_eq!(
            result.source_colors_at_least,
            Some(source_color_count::LIMIT)
        );
    }

    #[cfg(feature = "perceptual")]
    #[test]
    fn automatic_palette_is_lossless_after_the_first_reduction() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("complex.png");
        fs::write(&input, color_count_fixture(512)).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::AutomaticPalette,
            ..Request::default()
        };

        let first = execute(&request);
        assert!(first.ok, "{first:?}");
        let first_result = &first.results[0];
        assert!(first_result.lossy);
        assert_eq!(first_result.source_colors, Some(512));
        assert_eq!(first_result.source_colors_at_least, None);

        let first_output = first_result.output.as_ref().unwrap();
        let second = execute(&Request {
            inputs: vec![first_output.clone()],
            mode: CompressionMode::AutomaticPalette,
            ..Request::default()
        });
        assert!(second.ok, "{second:?}");
        let second_result = &second.results[0];
        assert!(!second_result.lossy);
        assert_eq!(second_result.pixel_identical, Some(true));
        assert!(
            second_result
                .source_colors
                .is_some_and(|count| count <= 256)
        );
        assert!(matches!(
            second_result.actual_mode.as_deref(),
            Some("exact_palette" | "lossless")
        ));
        let second_output = second_result.output.as_ref().unwrap();
        assert_eq!(
            image_data::decode(&fs::read(first_output).unwrap(), 1024 * 1024).unwrap(),
            image_data::decode(&fs::read(second_output).unwrap(), 1024 * 1024).unwrap()
        );
    }

    #[cfg(feature = "perceptual")]
    #[test]
    fn automatic_palette_protects_only_after_reaching_the_requested_limit() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("one-hundred-colors.png");
        fs::write(&input, color_count_fixture(100)).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::AutomaticPalette,
            max_colors: Some(64),
            ..Request::default()
        };

        let first = execute(&request);
        assert!(first.ok, "{first:?}");
        let first_result = &first.results[0];
        assert!(first_result.lossy);
        assert_eq!(first_result.source_colors, Some(100));

        let second = execute(&Request {
            inputs: vec![first_result.output.clone().unwrap()],
            mode: CompressionMode::AutomaticPalette,
            max_colors: Some(64),
            ..Request::default()
        });
        assert!(second.ok, "{second:?}");
        assert!(!second.results[0].lossy);
        assert!(
            second.results[0]
                .source_colors
                .is_some_and(|count| count <= 64)
        );
    }

    #[cfg(feature = "perceptual")]
    #[test]
    fn animated_color_reduction_falls_back_without_flattening() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("animated.png");
        fs::write(&input, animated_fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            mode: CompressionMode::Perceptual,
            fallback: Fallback::Lossless,
            ..Request::default()
        };

        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        assert_eq!(
            response.results[0].actual_mode.as_deref(),
            Some("lossless_fallback")
        );
        assert!(!response.results[0].lossy);
        let output = fs::read(response.results[0].output.as_ref().unwrap()).unwrap();
        assert!(png_document::inspect(&output, 1024).unwrap().is_animated());
    }

    #[test]
    fn animated_crop_is_rejected_instead_of_flattened() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("animated.png");
        fs::write(&input, animated_fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            canvas: Some(CanvasOptions {
                width: 1,
                height: 1,
                image_scale: 1.0,
                image_offset_x: 0,
                image_offset_y: 0,
            }),
            ..Request::default()
        };

        let response = execute(&request);
        assert!(!response.ok);
        assert!(
            response.results[0]
                .error
                .as_deref()
                .is_some_and(|message| message.contains("animated PNGs"))
        );
    }

    #[test]
    fn canvas_edits_are_written_even_when_the_result_is_larger() {
        let directory = tempfile::tempdir().unwrap();
        let input = directory.path().join("canvas.png");
        fs::write(&input, fixture()).unwrap();
        let request = Request {
            inputs: vec![input.to_string_lossy().into()],
            canvas: Some(CanvasOptions {
                width: 20,
                height: 20,
                image_scale: 1.0,
                image_offset_x: 9,
                image_offset_y: 9,
            }),
            output: OutputOptions {
                only_if_smaller: true,
                ..OutputOptions::default()
            },
            mode: CompressionMode::Lossless,
            ..Request::default()
        };

        let response = execute(&request);
        assert!(response.ok, "{response:?}");
        assert!(response.results[0].written);
        assert!(response.results[0].output.is_some());
    }
}
