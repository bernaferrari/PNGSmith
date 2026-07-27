use serde::{Deserialize, Serialize};

fn default_mode() -> CompressionMode {
    CompressionMode::SmartLossless
}
fn default_fallback() -> Fallback {
    Fallback::Lossless
}
fn default_colors() -> Option<u16> {
    Some(256)
}
fn default_level() -> u8 {
    4
}
fn default_suffix() -> String {
    "_min".into()
}
fn default_max_bytes() -> usize {
    512 * 1024 * 1024
}
fn default_quality_min() -> u8 {
    90
}
fn default_quality_max() -> u8 {
    100
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CompressionMode {
    SmartLossless,
    Lossless,
    #[serde(alias = "exact")]
    ExactPalette,
    Perceptual,
    #[serde(alias = "auto")]
    AutomaticPalette,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AutoColorStrategy {
    #[default]
    Balanced,
    Smaller,
}

impl AutoColorStrategy {
    pub const fn minimum_quality(self) -> u8 {
        match self {
            Self::Balanced => 88,
            Self::Smaller => 74,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default)]
pub struct AutomaticOptions {
    pub strategy: AutoColorStrategy,
    pub protect_existing_palette: bool,
}

impl Default for AutomaticOptions {
    fn default() -> Self {
        Self {
            strategy: AutoColorStrategy::default(),
            protect_existing_palette: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Fallback {
    Error,
    Lossless,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MetadataPolicy {
    #[default]
    Preserve,
    Safe,
    StripAll,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct OutputOptions {
    pub create_copy: bool,
    pub suffix: String,
    pub only_if_smaller: bool,
}

impl Default for OutputOptions {
    fn default() -> Self {
        Self {
            create_copy: true,
            suffix: default_suffix(),
            only_if_smaller: false,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct LosslessOptions {
    pub oxipng_level: u8,
    pub zopfli: bool,
    pub preserve_metadata: bool,
    pub metadata: MetadataPolicy,
    pub preserve_transparent_rgb: bool,
    pub allow_lossless_palette: bool,
    pub scale_16_bit: bool,
    pub max_decompressed_bytes: usize,
}

impl Default for LosslessOptions {
    fn default() -> Self {
        Self {
            oxipng_level: default_level(),
            zopfli: false,
            preserve_metadata: true,
            metadata: MetadataPolicy::Preserve,
            preserve_transparent_rgb: true,
            allow_lossless_palette: true,
            scale_16_bit: false,
            max_decompressed_bytes: default_max_bytes(),
        }
    }
}

impl LosslessOptions {
    pub fn effective_metadata(&self) -> MetadataPolicy {
        if self.metadata != MetadataPolicy::Preserve || self.preserve_metadata {
            self.metadata
        } else {
            MetadataPolicy::Safe
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct VerifyOptions {
    pub decoded_pixels: bool,
}

impl Default for VerifyOptions {
    fn default() -> Self {
        Self {
            decoded_pixels: true,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct PerceptualOptions {
    pub quality_min: u8,
    pub quality_max: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct CropOptions {
    pub x: u32,
    pub y: u32,
    pub width: u32,
    pub height: u32,
}

/// Places the source image on a transparent output canvas. Offsets are measured
/// from the canvas' top-left corner to the scaled image's top-left corner.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct CanvasOptions {
    pub width: u32,
    pub height: u32,
    pub image_scale: f64,
    pub image_offset_x: i32,
    pub image_offset_y: i32,
}

impl Default for PerceptualOptions {
    fn default() -> Self {
        Self {
            quality_min: default_quality_min(),
            quality_max: default_quality_max(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Request {
    pub inputs: Vec<String>,
    pub crop: Option<CropOptions>,
    pub canvas: Option<CanvasOptions>,
    pub mode: CompressionMode,
    pub max_colors: Option<u16>,
    pub fallback: Fallback,
    pub output: OutputOptions,
    pub lossless: LosslessOptions,
    pub perceptual: PerceptualOptions,
    pub automatic: AutomaticOptions,
    pub verify: VerifyOptions,
}

impl Default for Request {
    fn default() -> Self {
        Self {
            inputs: Vec::new(),
            crop: None,
            canvas: None,
            mode: default_mode(),
            max_colors: default_colors(),
            fallback: default_fallback(),
            output: OutputOptions::default(),
            lossless: LosslessOptions::default(),
            perceptual: PerceptualOptions::default(),
            automatic: AutomaticOptions::default(),
            verify: VerifyOptions::default(),
        }
    }
}

impl Request {
    pub fn validate(&self) -> Result<(), String> {
        if self.inputs.is_empty() {
            return Err("at least one input is required".into());
        }
        if self.lossless.oxipng_level > 6 {
            return Err("oxipng_level must be between 0 and 6".into());
        }
        if self.output.suffix.contains('/') || self.output.suffix.contains('\0') {
            return Err("output suffix must be a filename suffix".into());
        }
        if self
            .crop
            .is_some_and(|crop| crop.width == 0 || crop.height == 0)
        {
            return Err("crop width and height must be greater than zero".into());
        }
        if self.crop.is_some() && self.canvas.is_some() {
            return Err("crop and canvas cannot be used together".into());
        }
        if self.canvas.is_some_and(|canvas| {
            canvas.width == 0
                || canvas.height == 0
                || !canvas.image_scale.is_finite()
                || canvas.image_scale <= 0.0
        }) {
            return Err("canvas dimensions and image scale must be greater than zero".into());
        }
        if matches!(
            self.mode,
            CompressionMode::ExactPalette
                | CompressionMode::Perceptual
                | CompressionMode::AutomaticPalette
        ) {
            let colors = self
                .max_colors
                .ok_or("max_colors is required for palette modes")?;
            if !(2..=256).contains(&colors) {
                return Err("max_colors must be between 2 and 256".into());
            }
        }
        if self.perceptual.quality_min > self.perceptual.quality_max
            || self.perceptual.quality_max > 100
        {
            return Err("perceptual quality must be an ordered range from 0 through 100".into());
        }
        Ok(())
    }
}

pub fn builtin_profile(name: &str, inputs: Vec<String>) -> Result<Request, String> {
    let mut request = Request {
        inputs,
        ..Request::default()
    };
    match name {
        "smart-lossless" => {
            request.mode = CompressionMode::SmartLossless;
            request.lossless.metadata = MetadataPolicy::Safe;
            request.output.only_if_smaller = true;
        }
        "strict-lossless" => request.mode = CompressionMode::Lossless,
        "exact-256" => {
            request.mode = CompressionMode::ExactPalette;
            request.max_colors = Some(256);
            request.fallback = Fallback::Error;
        }
        "perceptual-256" => {
            request.mode = CompressionMode::Perceptual;
            request.max_colors = Some(256);
            request.lossless.metadata = MetadataPolicy::Safe;
        }
        "auto-balanced" => {
            request.mode = CompressionMode::AutomaticPalette;
            request.automatic.strategy = AutoColorStrategy::Balanced;
            request.lossless.metadata = MetadataPolicy::Safe;
        }
        "auto-smaller" => {
            request.mode = CompressionMode::AutomaticPalette;
            request.automatic.strategy = AutoColorStrategy::Smaller;
            request.lossless.metadata = MetadataPolicy::Safe;
        }
        "maximum-lossless" => {
            request.mode = CompressionMode::Lossless;
            request.lossless.oxipng_level = 6;
            request.lossless.zopfli = true;
            request.lossless.metadata = MetadataPolicy::Safe;
        }
        _ => return Err(format!("unknown profile '{name}'")),
    }
    Ok(request)
}
