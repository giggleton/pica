//! The NIF behind `Pica.Native`.
//!
//! Every function here must return an error term for bad font data rather than panic: Rustler turns
//! a panic into a raise, but a panic on font data is a bug.

mod font;
mod glyphs;
mod shaping;

use font::{FontResource, Info, LoadError};
use glyphs::{GlyphBox, GlyphError};
use rustler::{Binary, ResourceArc};
use shaping::{Direction, Glyph, Settings, ShapingError};

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

// Shaping stays on a normal scheduler too: measured on Lato, Source Serif 4 and Roboto, a label
// of a few words takes 10 to 15 microseconds. A font's first shaping prepares harfrust's layout
// tables, and loading plus that first call stayed under 700 microseconds.

/// Shapes `text` into glyphs with the caller's features, and its direction, script, language and
/// scale where given (`nil` leaves each to harfrust, and a missing scale means font units).
#[rustler::nif]
fn shape(
    resource: ResourceArc<FontResource>,
    text: &str,
    features: Vec<(String, u32)>,
    direction: Option<Direction>,
    script: Option<String>,
    language: Option<String>,
    scale: Option<i32>,
) -> Result<Vec<Glyph>, ShapingError> {
    let settings = Settings {
        features,
        direction,
        script,
        language,
        scale,
    };
    shaping::shape(&resource, text, settings)
}

rustler::init!("Elixir.Pica.Native");
