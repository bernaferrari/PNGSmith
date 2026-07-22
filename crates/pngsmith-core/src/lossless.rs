use crate::{
    Error,
    profile::{LosslessOptions, MetadataPolicy},
};

pub fn optimize(source: &[u8], config: &LosslessOptions) -> Result<Vec<u8>, Error> {
    let mut options = oxipng::Options::from_preset(config.oxipng_level.min(6));
    options.optimize_alpha = !config.preserve_transparent_rgb;
    options.scale_16 = config.scale_16_bit;
    options.bit_depth_reduction = true;
    options.color_type_reduction = true;
    options.palette_reduction = config.allow_lossless_palette;
    options.grayscale_reduction = true;
    options.strip = match config.effective_metadata() {
        MetadataPolicy::Preserve => oxipng::StripChunks::None,
        MetadataPolicy::Safe => oxipng::StripChunks::Safe,
        MetadataPolicy::StripAll => oxipng::StripChunks::All,
    };
    options.max_decompressed_size = Some(config.max_decompressed_bytes);
    if config.zopfli {
        options.deflater = oxipng::Deflater::Zopfli(oxipng::ZopfliOptions::default());
    }
    oxipng::optimize_from_memory(source, &options).map_err(Error::from)
}
