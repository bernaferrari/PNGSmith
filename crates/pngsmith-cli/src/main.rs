use anyhow::{Context, Result};
use clap::{Parser, Subcommand, ValueEnum};
use pngsmith_core::{
    AutoColorStrategy, CompressionMode, Fallback, MetadataPolicy, Request, builtin_profile,
};
use std::{
    io::{self, Read},
    path::PathBuf,
    process::ExitCode,
};

#[derive(Parser)]
#[command(
    name = "pngsmith",
    version,
    about = "Self-contained PNG compression powered by embedded OxiPNG"
)]
struct Cli {
    #[command(subcommand)]
    command: Option<Command>,
    #[arg(value_name = "PNG", global = true)]
    inputs: Vec<PathBuf>,
    #[arg(long, value_enum, default_value = "smart-lossless", global = true)]
    mode: CliMode,
    #[arg(long, default_value_t = 256, global = true)]
    colors: u16,
    #[arg(long, value_enum, default_value = "lossless", global = true)]
    fallback: CliFallback,
    #[arg(long, value_enum, default_value = "balanced", global = true)]
    auto_strategy: CliAutoStrategy,
    #[arg(long, global = true)]
    replace: bool,
    #[arg(long, default_value = "_min", global = true)]
    suffix: String,
    #[arg(long, global = true)]
    only_if_smaller: bool,
    #[arg(long, default_value_t = 4, global = true)]
    oxipng_level: u8,
    #[arg(long, global = true)]
    zopfli: bool,
    #[arg(long, value_enum, default_value = "preserve", global = true)]
    metadata: CliMetadata,
    #[arg(long, global = true)]
    no_verify: bool,
    #[arg(long, global = true)]
    json: bool,
}

#[derive(Subcommand)]
enum Command {
    Minify {
        #[arg(long)]
        profile: Option<String>,
        #[arg(value_name = "PNG")]
        files: Vec<PathBuf>,
    },
    ExecuteJson {
        #[arg(long)]
        request: Option<String>,
    },
    Profiles,
}

#[derive(Clone, Copy, ValueEnum)]
enum CliMode {
    SmartLossless,
    Lossless,
    Exact,
    Perceptual,
    Auto,
}
#[derive(Clone, Copy, ValueEnum)]
enum CliAutoStrategy {
    Balanced,
    Smaller,
}
#[derive(Clone, Copy, ValueEnum)]
enum CliFallback {
    Error,
    Lossless,
}
#[derive(Clone, Copy, ValueEnum)]
enum CliMetadata {
    Preserve,
    Safe,
    StripAll,
}

fn main() -> ExitCode {
    match run() {
        Ok(true) => ExitCode::SUCCESS,
        Ok(false) => ExitCode::FAILURE,
        Err(error) => {
            eprintln!("pngsmith: {error:#}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<bool> {
    let cli = Cli::parse();
    let result: Result<bool> = match &cli.command {
        Some(Command::ExecuteJson { request }) => {
            let json = match request {
                Some(value) => value.clone(),
                None => {
                    let mut value = String::new();
                    io::stdin().read_to_string(&mut value)?;
                    value
                }
            };
            let response = pngsmith_core::execute_json(&json)?;
            println!("{response}");
            Ok(serde_json::from_str::<serde_json::Value>(&response)?["ok"]
                .as_bool()
                .unwrap_or(false))
        }
        Some(Command::Profiles) => {
            println!(
                "smart-lossless\nstrict-lossless\nexact-256\nperceptual-256\nauto-balanced\nauto-smaller\nmaximum-lossless"
            );
            Ok(true)
        }
        _ => {
            let (profile, mut files) = match &cli.command {
                Some(Command::Minify { profile, files }) => (profile.as_deref(), files.clone()),
                None => (None, Vec::new()),
                _ => unreachable!(),
            };
            files.extend(cli.inputs.clone());
            let strings: Vec<String> = files
                .into_iter()
                .map(|p| p.to_string_lossy().into_owned())
                .collect();
            if strings.is_empty() {
                anyhow::bail!("supply one or more PNG files");
            }
            let mut request = if let Some(name) = profile {
                builtin_profile(name, strings).map_err(anyhow::Error::msg)?
            } else {
                Request {
                    inputs: strings,
                    ..Request::default()
                }
            };
            if profile.is_none() {
                request.mode = match cli.mode {
                    CliMode::SmartLossless => CompressionMode::SmartLossless,
                    CliMode::Lossless => CompressionMode::Lossless,
                    CliMode::Exact => CompressionMode::ExactPalette,
                    CliMode::Perceptual => CompressionMode::Perceptual,
                    CliMode::Auto => CompressionMode::AutomaticPalette,
                };
                request.max_colors = Some(cli.colors);
                request.fallback = match cli.fallback {
                    CliFallback::Error => Fallback::Error,
                    CliFallback::Lossless => Fallback::Lossless,
                };
                request.automatic.strategy = match cli.auto_strategy {
                    CliAutoStrategy::Balanced => AutoColorStrategy::Balanced,
                    CliAutoStrategy::Smaller => AutoColorStrategy::Smaller,
                };
                request.output.create_copy = !cli.replace;
                request.output.suffix = cli.suffix;
                request.output.only_if_smaller = cli.only_if_smaller;
                request.lossless.oxipng_level = cli.oxipng_level;
                request.lossless.zopfli = cli.zopfli;
                request.lossless.metadata = match cli.metadata {
                    CliMetadata::Preserve => MetadataPolicy::Preserve,
                    CliMetadata::Safe => MetadataPolicy::Safe,
                    CliMetadata::StripAll => MetadataPolicy::StripAll,
                };
                request.verify.decoded_pixels = !cli.no_verify;
            }
            let response = pngsmith_core::execute(&request);
            if cli.json {
                println!("{}", serde_json::to_string_pretty(&response)?);
            } else {
                for result in &response.results {
                    if let Some(error) = &result.error {
                        eprintln!("{}: {error}", result.input);
                    } else if let Some(output) = &result.output {
                        let budget = result
                            .color_budget
                            .map(|value| format!(", auto budget {value}"))
                            .unwrap_or_default();
                        println!(
                            "{} -> {} ({} -> {} bytes, {}{})",
                            result.input,
                            output,
                            result.original_bytes.unwrap_or(0),
                            result.output_bytes.unwrap_or(0),
                            result.actual_mode.as_deref().unwrap_or("unknown"),
                            budget
                        );
                    } else {
                        println!(
                            "{}: {}",
                            result.input,
                            result.skipped_reason.as_deref().unwrap_or("not written")
                        );
                    }
                }
            }
            Ok(response.ok)
        }
    };
    result.context("compression failed")
}
