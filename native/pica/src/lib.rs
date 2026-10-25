//! The NIF behind `Pica.Native`.
//!
//! Every function here must return an error term for bad font data rather than panic: Rustler turns
//! a panic into a raise, but a panic on font data is a bug.

mod font;

use font::{FontResource, Info, LoadError};
use rustler::{Binary, ResourceArc};

/// The crate's own version, so a caller can see which build of the NIF is loaded.
#[rustler::nif]
fn crate_version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// Loads the font at `index` from a font file's bytes. Decoding a WOFF2 and reading the tables can
/// take milliseconds, so this runs on a dirty scheduler.
#[rustler::nif(schedule = "DirtyCpu")]
fn load(bytes: Binary, index: u64) -> Result<(ResourceArc<FontResource>, Info), LoadError> {
    font::load(bytes.as_slice(), index).map(|(resource, info)| (ResourceArc::new(resource), info))
}

rustler::init!("Elixir.Pica.Native");
