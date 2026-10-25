//! Measuring glyphs, all in font units at the font's default location: the glyph each character
//! maps to, each glyph's nominal advance, and each glyph's control box.
//!
//! The caller has checked every glyph id against the font's glyph count, but an id past the end
//! is still an error here rather than a panic.

use crate::font::{FontResource, outline_collection};
use read_fonts::ReadError;
use rustler::{Atom, NifTaggedEnum, NifUntaggedEnum};
use skrifa::instance::{LocationRef, Size};
use skrifa::metrics::GlyphMetrics;
use skrifa::outline::DrawSettings;
use skrifa::outline::pen::ControlBoundsPen;
use skrifa::{GlyphId, MetadataProvider};

rustler::atoms! {
    none,
}

/// A glyph's control box, `{x_min, y_min, x_max, y_max}`, or `:none` for a glyph with no outline.
#[derive(NifUntaggedEnum)]
pub enum GlyphBox {
    Corners((i32, i32, i32, i32)),
    Empty(Atom),
}

/// Why glyphs could not be measured; the Elixir side receives the variant as a tagged tuple.
/// Load has read the font's directory, metrics and outline table, so `UnreadableFont` is not
/// expected; `MalformedGlyph` is one glyph's data, which load does not read.
#[derive(NifTaggedEnum, Debug, PartialEq)]
pub enum GlyphError {
    UnreadableFont(String),
    MalformedGlyph(u32, String),
}

impl From<ReadError> for GlyphError {
    fn from(error: ReadError) -> Self {
        GlyphError::UnreadableFont(error.to_string())
    }
}

impl GlyphError {
    fn malformed_glyph(glyph_id: u32, detail: impl ToString) -> Self {
        GlyphError::MalformedGlyph(glyph_id, detail.to_string())
    }
}

/// The glyph each character of `text` maps to through the font's character map, 0 (the
/// `.notdef` glyph) for a character the font lacks.
pub fn glyph_ids(resource: &FontResource, text: &str) -> Result<Vec<u32>, GlyphError> {
    let charmap = resource.font()?.charmap();
    Ok(text
        .chars()
        .map(|character| charmap.map(character).map_or(0, GlyphId::to_u32))
        .collect())
}

/// Each glyph's advance width as the font's `hmtx` table gives it, before shaping.
pub fn nominal_advances(
    resource: &FontResource,
    glyph_ids: &[u32],
) -> Result<Vec<u32>, GlyphError> {
    let font = resource.font()?;
    let metrics = GlyphMetrics::new(&font, Size::unscaled(), LocationRef::default());
    glyph_ids
        .iter()
        .map(|&glyph_id| {
            // Unscaled, skrifa returns the table's whole number of font units, never below zero.
            metrics
                .advance_width(GlyphId::new(glyph_id))
                .map(|advance| advance as u32)
                .ok_or_else(|| GlyphError::malformed_glyph(glyph_id, "it has no advance width"))
        })
        .collect()
}

/// Each glyph's control box: the box around every point of its outline, on-curve and off, as
/// FreeType computes it, whatever box the font stores. skrifa draws unscaled outlines as FreeType
/// loads them, so a TrueType composite that scales a component has each point rounded to a whole
/// font unit; a CFF coordinate can still fall between units, and its corner is rounded outward.
pub fn glyph_boxes(
    resource: &FontResource,
    glyph_ids: &[u32],
) -> Result<Vec<GlyphBox>, GlyphError> {
    let font = resource.font()?;
    let Some(outlines) = outline_collection(&font, resource.outlines()) else {
        // A font with no outline table draws nothing.
        return Ok(glyph_ids.iter().map(|_| GlyphBox::Empty(none())).collect());
    };
    glyph_ids
        .iter()
        .map(|&glyph_id| {
            // skrifa answers `None` for a glyph whose data does not read; a glyph with no points
            // is drawn, into an empty box.
            let outline = outlines.get(GlyphId::new(glyph_id)).ok_or_else(|| {
                GlyphError::malformed_glyph(glyph_id, "its outline data does not read")
            })?;
            let mut pen = ControlBoundsPen::default();
            outline
                .draw(
                    DrawSettings::unhinted(Size::unscaled(), LocationRef::default()),
                    &mut pen,
                )
                .map_err(|error| GlyphError::malformed_glyph(glyph_id, error))?;
            Ok(match pen.bounding_box() {
                Some(corners) => GlyphBox::Corners((
                    corners.x_min.floor() as i32,
                    corners.y_min.floor() as i32,
                    corners.x_max.ceil() as i32,
                    corners.y_max.ceil() as i32,
                )),
                None => GlyphBox::Empty(none()),
            })
        })
        .collect()
}
