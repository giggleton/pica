//! The NIF behind `Pica.Native`.
//!
//! Every function here must return an error term for bad font data rather than panic: Rustler turns
//! a panic into a raise, but a panic on font data is a bug.

mod font;
mod glyphs;
mod installed;
mod shaping;

use font::{FontResource, Info, LoadError};
use glyphs::{GlyphBox, GlyphError, GlyphOutline};
use installed::InstalledFace;
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

// The character map and the advances stay on a normal scheduler: measured on the test fonts, a
// call for a hundred glyphs takes a few microseconds, and a label is a handful.

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

// Boxes and outlines draw each glyph's outline. Boxing costs up to about 5 microseconds a glyph
// and drawing up to about 6 (bench/glyph_outlines.exs: a label's 24 glyphs drawn in 25 to 75
// microseconds; the slowest hundred glyphs of a test font, CFF, boxed in 0.46 ms and drawn in
// 0.57 ms; every glyph of a font boxed in 1.4 to 6 ms and drawn in 7 to 20 ms), so up to 64
// glyphs, every label, measure on a normal scheduler in under 0.4 ms, and more on a dirty one.
// `Pica.glyph_boxes/2` and `Pica.glyph_outlines/2` each choose between two names, which share
// one function.

/// Each glyph's control box, or `:none` for a glyph with no outline. For up to 64 glyphs.
#[rustler::nif]
fn glyph_boxes(
    resource: ResourceArc<FontResource>,
    glyph_ids: Vec<u32>,
) -> Result<Vec<GlyphBox>, GlyphError> {
    glyphs::glyph_boxes(&resource, &glyph_ids)
}

/// `glyph_boxes`, on a dirty CPU scheduler, for more than 64 glyphs.
#[rustler::nif(schedule = "DirtyCpu")]
fn glyph_boxes_many_glyphs(
    resource: ResourceArc<FontResource>,
    glyph_ids: Vec<u32>,
) -> Result<Vec<GlyphBox>, GlyphError> {
    glyphs::glyph_boxes(&resource, &glyph_ids)
}

/// Each glyph's outline, as drawing commands in font units, or `:none` for a glyph that draws
/// nothing. For up to 64 glyphs.
#[rustler::nif]
fn glyph_outlines(
    resource: ResourceArc<FontResource>,
    glyph_ids: Vec<u32>,
) -> Result<Vec<GlyphOutline>, GlyphError> {
    glyphs::glyph_outlines(&resource, &glyph_ids)
}

/// `glyph_outlines`, on a dirty CPU scheduler, for more than 64 glyphs.
#[rustler::nif(schedule = "DirtyCpu")]
fn glyph_outlines_many_glyphs(
    resource: ResourceArc<FontResource>,
    glyph_ids: Vec<u32>,
) -> Result<Vec<GlyphOutline>, GlyphError> {
    glyphs::glyph_outlines(&resource, &glyph_ids)
}

// Shaping costs about 0.45 microseconds a character once the font keeps a shape plan for the
// text's settings (bench/shaping.exs: 100 labels in about 0.35 ms, building a plan per call about
// twice that), so text of up to 1,000 bytes, every label, shapes on a normal scheduler in under
// half a millisecond, and longer text on a dirty one. `Pica.shape/3` chooses between the two
// names, which share one function.

/// Shapes `text` into glyphs with the caller's features, and its direction, script, language and
/// scale where given (`nil` leaves each to harfrust, and a missing scale means font units). For
/// text of up to 1,000 bytes.
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

/// `shape`, on a dirty CPU scheduler, for text longer than 1,000 bytes.
#[rustler::nif(schedule = "DirtyCpu")]
fn shape_long_text(
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

/// Every installed face, or every face in `directory` (`nil` for the installed fonts). Scanning
/// reads every font file on the machine, so this runs on a dirty IO scheduler.
#[rustler::nif(schedule = "DirtyIo")]
fn installed_faces(directory: Option<String>) -> Vec<InstalledFace> {
    installed::installed_faces(directory)
}

rustler::init!("Elixir.Pica.Native");
