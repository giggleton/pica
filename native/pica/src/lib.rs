//! The NIF behind `Pica.Native`.
//!
//! Every function here must return an error term for bad font data rather than panic: Rustler turns
//! a panic into a raise, but a panic on font data is a bug.

mod font;
mod glyphs;

use font::{FontResource, Info, LoadError};
use glyphs::{GlyphBox, GlyphError};
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

// The glyph measurements stay on a normal scheduler: measured on the test fonts, a call for a
// hundred glyphs takes well under a millisecond (boxes tens of microseconds for TrueType, under
// two hundred for CFF; advances and the character map a few), and a label is a handful.

/// The glyph each character of `text` maps to, 0 for a character the font lacks.
#[rustler::nif]
fn glyph_ids(resource: ResourceArc<FontResource>, text: &str) -> Result<Vec<u32>, GlyphError> {
    glyphs::glyph_ids(&resource, text)
}

/// Each glyph's advance width as the font stores it.
#[rustler::nif]
fn nominal_advances(
    resource: ResourceArc<FontResource>,
    glyph_ids: Vec<u32>,
) -> Result<Vec<u32>, GlyphError> {
    glyphs::nominal_advances(&resource, &glyph_ids)
}

/// Each glyph's control box, or `:none` for a glyph with no outline.
#[rustler::nif]
fn glyph_boxes(
    resource: ResourceArc<FontResource>,
    glyph_ids: Vec<u32>,
) -> Result<Vec<GlyphBox>, GlyphError> {
    glyphs::glyph_boxes(&resource, &glyph_ids)
}

rustler::init!("Elixir.Pica.Native");
