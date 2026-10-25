//! Shaping text with harfrust, in font units at the font's default location.
//!
//! The text goes into harfrust's buffer one code point at a time, each with its index as its
//! cluster, so clusters count characters, as hb-shape's do, not the UTF-8 bytes harfrust's
//! `push_str` would give. Direction, script and language are the caller's where given; harfrust
//! guesses the direction and script from the text otherwise, and leaves the language unset, so
//! the font's default rules apply and nothing depends on the machine's locale. HarfBuzz's default
//! features for the script are on, and the caller's features are applied over them to the whole
//! text.
//!
//! The caller has checked every setting's form: four-byte feature tags, four-letter scripts and
//! language tags of letters, digits, `-` and `_`. A setting that is still malformed here is an
//! error, never a panic.

use crate::font::FontResource;
use harfrust::{Buffer, Feature, Language, Script, ShapeOptions, ShaperFont, Tag};
use rustler::{NifStruct, NifTaggedEnum, NifUnitEnum};
use std::str::FromStr;

/// One shaped glyph, as `%Pica.Glyph{}`.
#[derive(NifStruct)]
#[module = "Pica.Glyph"]
pub struct Glyph {
    glyph_id: u32,
    cluster: u32,
    x_advance: i32,
    nominal_advance: i32,
    x_offset: i32,
    y_offset: i32,
}

/// The directions a caller may set; vertical text is not shaped.
#[derive(NifUnitEnum, Clone, Copy)]
pub enum Direction {
    LeftToRight,
    RightToLeft,
}

impl From<Direction> for harfrust::Direction {
    fn from(direction: Direction) -> Self {
        match direction {
            Direction::LeftToRight => harfrust::Direction::LeftToRight,
            Direction::RightToLeft => harfrust::Direction::RightToLeft,
        }
    }
}

/// Why text could not be shaped; the Elixir side receives the variant as a tagged tuple. The
/// caller's checks and harfrust's own leave both unexpected: a setting the caller should have
/// refused, or shaping failing, which harfrust does only on a buffer set up wrongly or memory
/// running out, never on the font's data.
#[derive(NifTaggedEnum, Debug, PartialEq)]
pub enum ShapingError {
    InvalidSetting(String),
    ShapingFailed(String),
}

/// What the caller set; `None` leaves the setting to harfrust.
pub struct Settings {
    pub features: Vec<(String, u32)>,
    pub direction: Option<Direction>,
    pub script: Option<String>,
    pub language: Option<String>,
}

/// Shapes `text` into glyphs, in font units.
pub fn shape(
    resource: &FontResource,
    text: &str,
    settings: Settings,
) -> Result<Vec<Glyph>, ShapingError> {
    let features = settings
        .features
        .iter()
        .map(|(tag, value)| Ok(Feature::new(tag_of(tag)?, *value, ..)))
        .collect::<Result<Vec<_>, ShapingError>>()?;
    let mut buffer = Buffer::new();
    let codepoints: Vec<u32> = text.chars().map(u32::from).collect();
    buffer.push_codepoints(&codepoints);
    if !buffer.allocation_successful() {
        return Err(ShapingError::ShapingFailed(
            "the text's buffer could not be allocated".to_string(),
        ));
    }
    if let Some(direction) = settings.direction {
        buffer.set_direction(direction.into());
    }
    if let Some(script) = settings.script {
        buffer.set_script(Some(script_of(&script)?));
    }
    if let Some(language) = settings.language {
        buffer.set_language(Some(language_of(&language)?));
    }
    buffer.guess_segment_properties();

    let shaper_font = ShaperFont::new(resource.shaping_font());
    harfrust::shape(
        &shaper_font,
        &mut buffer,
        ShapeOptions::new().features(&features),
    )
    .map_err(|error| ShapingError::ShapingFailed(error.to_string()))?;

    Ok(buffer
        .glyph_infos()
        .iter()
        .zip(buffer.glyph_positions())
        .map(|(info, position)| Glyph {
            glyph_id: info.glyph_id,
            cluster: info.cluster,
            x_advance: position.x_advance,
            nominal_advance: shaper_font.glyph_h_advance(info.glyph_id.into()),
            x_offset: position.x_offset,
            y_offset: position.y_offset,
        })
        .collect())
}

fn tag_of(tag: &str) -> Result<Tag, ShapingError> {
    <[u8; 4]>::try_from(tag.as_bytes())
        .map(|bytes| Tag::new(&bytes))
        .map_err(|_| ShapingError::InvalidSetting(format!("feature tag {tag:?}")))
}

// harfrust takes any four letters for a script, adjusting their case, as HarfBuzz does.
fn script_of(script: &str) -> Result<Script, ShapingError> {
    Script::from_str(script)
        .ok()
        .filter(|_| script.len() == 4 && script.bytes().all(|byte| byte.is_ascii_alphabetic()))
        .ok_or_else(|| ShapingError::InvalidSetting(format!("script {script:?}")))
}

fn language_of(language: &str) -> Result<Language, ShapingError> {
    Language::from_str(language)
        .map_err(|_| ShapingError::InvalidSetting(format!("language {language:?}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_feature_tag_must_be_four_bytes() {
        assert!(tag_of("kern").is_ok());
        assert_eq!(
            tag_of("kerning").err(),
            Some(ShapingError::InvalidSetting(
                "feature tag \"kerning\"".to_string()
            ))
        );
    }

    #[test]
    fn a_script_must_be_four_letters_in_any_case() {
        assert_eq!(script_of("arab").ok(), Some(Script::ARABIC));
        assert!(script_of("Arabic").is_err());
        assert!(script_of("Ar1b").is_err());
    }

    #[test]
    fn an_empty_language_is_refused() {
        assert!(language_of("").is_err());
        assert_eq!(
            language_of("en_US")
                .ok()
                .map(|tag| tag.as_str().to_string()),
            Some("en-us".to_string())
        );
    }
}
