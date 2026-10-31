//! Measuring glyphs, all in font units at the font's default location: the glyph each character
//! maps to, each glyph's nominal advance, each glyph's control box, and each glyph's outline.
//!
//! The caller has checked every glyph id against the font's glyph count, but an id past the end
//! is still an error here rather than a panic.

use crate::font::{FontResource, outline_collection};
use read_fonts::ReadError;
use rustler::{Atom, Encoder, Env, NifTaggedEnum, NifUntaggedEnum, Term};
use skrifa::instance::{LocationRef, Size};
use skrifa::metrics::GlyphMetrics;
use skrifa::outline::pen::{ControlBoundsPen, OutlinePen, PathStyle};
use skrifa::outline::{DrawSettings, OutlineGlyphCollection};
use skrifa::{GlyphId, MetadataProvider};

rustler::atoms! {
    none,
    move_to = "move",
    line,
    quad,
    cubic,
    close,
}

/// A glyph's control box, `{x_min, y_min, x_max, y_max}`, or `:none` for a glyph with no outline.
#[derive(NifUntaggedEnum)]
pub enum GlyphBox {
    Corners((i32, i32, i32, i32)),
    Empty(Atom),
}

/// A glyph's outline, as the commands that draw it, or `:none` for a glyph that draws nothing.
pub enum GlyphOutline {
    Commands(Vec<OutlineCommand>),
    Empty,
}

/// One drawing command, in font units as skrifa draws it, encoded as a flat tuple:
/// `{:move, x, y}`, `{:line, x, y}`, `{:quad, control_x, control_y, x, y}`,
/// `{:cubic, first_control_x, first_control_y, second_control_x, second_control_y, x, y}`, or
/// `:close`.
pub enum OutlineCommand {
    Move(f32, f32),
    Line(f32, f32),
    Quad(f32, f32, f32, f32),
    Cubic(f32, f32, f32, f32, f32, f32),
    Close,
}

impl Encoder for GlyphOutline {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            GlyphOutline::Commands(commands) => commands.encode(env),
            GlyphOutline::Empty => none().encode(env),
        }
    }
}

impl Encoder for OutlineCommand {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match *self {
            OutlineCommand::Move(x, y) => (move_to(), x, y).encode(env),
            OutlineCommand::Line(x, y) => (line(), x, y).encode(env),
            OutlineCommand::Quad(control_x, control_y, x, y) => {
                (quad(), control_x, control_y, x, y).encode(env)
            }
            OutlineCommand::Cubic(
                first_control_x,
                first_control_y,
                second_control_x,
                second_control_y,
                x,
                y,
            ) => (
                cubic(),
                first_control_x,
                first_control_y,
                second_control_x,
                second_control_y,
                x,
                y,
            )
                .encode(env),
            OutlineCommand::Close => close().encode(env),
        }
    }
}

/// A pen that keeps every command skrifa draws, in order.
#[derive(Default)]
struct RecordingPen {
    commands: Vec<OutlineCommand>,
}

impl OutlinePen for RecordingPen {
    fn move_to(&mut self, x: f32, y: f32) {
        self.commands.push(OutlineCommand::Move(x, y));
    }

    fn line_to(&mut self, x: f32, y: f32) {
        self.commands.push(OutlineCommand::Line(x, y));
    }

    fn quad_to(&mut self, control_x: f32, control_y: f32, x: f32, y: f32) {
        self.commands
            .push(OutlineCommand::Quad(control_x, control_y, x, y));
    }

    fn curve_to(
        &mut self,
        first_control_x: f32,
        first_control_y: f32,
        second_control_x: f32,
        second_control_y: f32,
        x: f32,
        y: f32,
    ) {
        self.commands.push(OutlineCommand::Cubic(
            first_control_x,
            first_control_y,
            second_control_x,
            second_control_y,
            x,
            y,
        ));
    }

    fn close(&mut self) {
        self.commands.push(OutlineCommand::Close);
    }
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
            // A glyph with no points is drawn, into an empty box.
            let mut pen = ControlBoundsPen::default();
            draw(&outlines, glyph_id, &mut pen)?;
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

/// Each glyph's outline as skrifa draws it, unscaled and unhinted, in FreeType's path style: a
/// contour whose first point is off the curve starts at its last point, or halfway between its
/// last and first when both are off it, as FreeType starts it. Quadratic runs arrive split at
/// their implied on-curve points, and a contour closes without a line back to its start.
/// TrueType coordinates are whole font units, a scaled composite's points rounded as FreeType
/// rounds them unscaled; CFF coordinates can fall between units, and are kept as skrifa's `f32`.
pub fn glyph_outlines(
    resource: &FontResource,
    glyph_ids: &[u32],
) -> Result<Vec<GlyphOutline>, GlyphError> {
    let font = resource.font()?;
    let Some(outlines) = outline_collection(&font, resource.outlines()) else {
        // A font with no outline table draws nothing.
        return Ok(glyph_ids.iter().map(|_| GlyphOutline::Empty).collect());
    };
    glyph_ids
        .iter()
        .map(|&glyph_id| {
            let mut pen = RecordingPen::default();
            draw(&outlines, glyph_id, &mut pen)?;
            Ok(if pen.commands.is_empty() {
                GlyphOutline::Empty
            } else {
                GlyphOutline::Commands(pen.commands)
            })
        })
        .collect()
}

// Draws one glyph into `pen`, unscaled and unhinted at the default location, in FreeType's path
// style. skrifa answers `None` for a glyph whose data does not read; a glyph with no points is
// drawn, and the pen receives nothing.
fn draw(
    outlines: &OutlineGlyphCollection,
    glyph_id: u32,
    pen: &mut impl OutlinePen,
) -> Result<(), GlyphError> {
    let outline = outlines
        .get(GlyphId::new(glyph_id))
        .ok_or_else(|| GlyphError::malformed_glyph(glyph_id, "its outline data does not read"))?;
    let settings = DrawSettings::unhinted(Size::unscaled(), LocationRef::default())
        .with_path_style(PathStyle::FreeType);
    outline
        .draw(settings, pen)
        .map(|_metrics| ())
        .map_err(|error| GlyphError::malformed_glyph(glyph_id, error))
}
