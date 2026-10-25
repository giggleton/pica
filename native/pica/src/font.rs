//! Loading a font: decoding its container, choosing the font in a collection, checking that the
//! tables Pica reads are present and inside the data and that its metrics and outlines read, and
//! reading the font's information.

use read_fonts::tables::name::Encoding;
use read_fonts::types::{NameId, Tag};
use read_fonts::{FileRef, FontRef, ReadError, TableProvider};
use rustler::{NifMap, NifTaggedEnum, NifUnitEnum};
use skrifa::OutlineGlyphCollection;
use skrifa::outline::OutlineGlyphFormat;

/// A loaded font: the decoded bytes of its file, which font of the file it is, and the table
/// that draws its glyphs.
pub struct FontResource {
    bytes: Vec<u8>,
    index: u32,
    outlines: Outlines,
}

#[rustler::resource_impl]
impl rustler::Resource for FontResource {}

impl FontResource {
    pub fn font(&self) -> Result<FontRef<'_>, ReadError> {
        FontRef::from_index(&self.bytes, self.index)
    }

    pub fn outlines(&self) -> Outlines {
        self.outlines
    }
}

/// What the bytes were when they arrived.
#[derive(NifUnitEnum, Clone, Copy)]
pub enum Container {
    Sfnt,
    Collection,
    Woff,
    Woff2,
}

/// The table that draws the font's glyphs.
#[derive(NifUnitEnum, Clone, Copy)]
pub enum Outlines {
    Truetype,
    Cff,
    Cff2,
    None,
}

#[derive(NifMap)]
pub struct Axis {
    tag: String,
    minimum: f64,
    default: f64,
    maximum: f64,
}

/// The font's information, as `Pica.info/1` reports it.
#[derive(NifMap)]
pub struct Info {
    index: u32,
    font_count: u32,
    container: Container,
    outlines: Outlines,
    family: Option<String>,
    subfamily: Option<String>,
    units_per_em: u16,
    ascender: i16,
    descender: i16,
    line_gap: i16,
    weight_class: Option<u16>,
    italic: bool,
    glyph_count: u16,
    axes: Vec<Axis>,
}

/// Why a font did not load; the Elixir side receives the variant as an atom or a tagged tuple.
#[derive(NifTaggedEnum, Debug, PartialEq)]
pub enum LoadError {
    UnknownFormat,
    Truncated,
    IndexOutOfRange(u32),
    MissingTable(String),
    Malformed(String),
}

impl From<ReadError> for LoadError {
    fn from(error: ReadError) -> Self {
        match error {
            ReadError::OutOfBounds => LoadError::Truncated,
            ReadError::TableIsMissing(tag) => LoadError::MissingTable(tag.to_string()),
            other => LoadError::Malformed(other.to_string()),
        }
    }
}

// The tables Pica reads to describe a font and measure its glyphs; a font without one of them
// does not load.
const REQUIRED_TABLES: [&[u8; 4]; 5] = [b"head", b"hhea", b"hmtx", b"maxp", b"name"];

/// Loads the font at `index` from a file's bytes.
pub fn load(bytes: &[u8], index: u64) -> Result<(FontResource, Info), LoadError> {
    let (container, decoded) = decode(bytes)?;
    let font_count = match FileRef::new(&decoded)? {
        FileRef::Font(_) => 1,
        FileRef::Collection(collection) => collection.len(),
    };
    let index = u32::try_from(index)
        .ok()
        .filter(|index| *index < font_count)
        .ok_or(LoadError::IndexOutOfRange(font_count))?;
    let outlines = {
        let font = FontRef::from_index(&decoded, index)?;
        check_tables(&font)?;
        let outlines = outlines(&font);
        check_glyphs(&font, outlines)?;
        outlines
    };
    let resource = FontResource {
        bytes: decoded,
        index,
        outlines,
    };
    let info = read_info(&resource.font()?, container, index, font_count, outlines)?;
    Ok((resource, info))
}

// The container is told by the file's first four bytes; WOFF and WOFF2 are decoded to the plain
// font (or collection) they wrap.
fn decode(bytes: &[u8]) -> Result<(Container, Vec<u8>), LoadError> {
    match bytes.get(0..4) {
        Some([0, 1, 0, 0] | b"true" | b"OTTO") => Ok((Container::Sfnt, bytes.to_vec())),
        Some(b"ttcf") => Ok((Container::Collection, bytes.to_vec())),
        Some(b"wOFF") => wuff::decompress_woff1(bytes)
            .map(|decoded| (Container::Woff, decoded))
            .map_err(|_| LoadError::Malformed("the WOFF data does not decode".to_string())),
        Some(b"wOF2") => wuff::decompress_woff2(bytes)
            .map(|decoded| (Container::Woff2, decoded))
            .map_err(|_| LoadError::Malformed("the WOFF2 data does not decode".to_string())),
        _ => Err(LoadError::UnknownFormat),
    }
}

// The table directory must hold every record it declares, and every table must lie inside the
// data: read-fonts reads as many records as fit, so a cut-off file would otherwise read as one
// missing its tables. Then the tables Pica reads must be listed.
fn check_tables(font: &FontRef) -> Result<(), LoadError> {
    let data_length = font.data().len();
    let directory = font.table_directory();
    let records = directory.table_records();
    if records.len() != usize::from(directory.num_tables()) {
        return Err(LoadError::Truncated);
    }
    let all_inside = records.iter().all(|record| {
        usize::try_from(record.offset())
            .ok()
            .zip(usize::try_from(record.length()).ok())
            .and_then(|(offset, length)| offset.checked_add(length))
            .is_some_and(|end| end <= data_length)
    });
    if !all_inside {
        return Err(LoadError::Truncated);
    }
    match REQUIRED_TABLES
        .iter()
        .find(|tag| !has_table(font, Tag::new(tag)))
    {
        Some(tag) => Err(LoadError::MissingTable(Tag::new(tag).to_string())),
        None => Ok(()),
    }
}

// The glyph measurements read the advance widths and draw the outlines, so both must read: the
// widths for as many glyphs as the font declares, and the outlines in the table `outlines` names.
fn check_glyphs(font: &FontRef, outlines: Outlines) -> Result<(), LoadError> {
    font.h_glyph_metric_records()?;
    let table = match (outlines, outline_collection(font, outlines)) {
        (Outlines::None, _) | (_, Some(_)) => return Ok(()),
        (Outlines::Truetype, None) => "glyf",
        (Outlines::Cff, None) => "CFF",
        (Outlines::Cff2, None) => "CFF2",
    };
    Err(LoadError::Malformed(format!(
        "the {table} outlines do not read"
    )))
}

/// The font's outlines, read from the table `outlines` names; `None` for a font with no outlines.
/// The format is named rather than left to skrifa, which would prefer an experimental `VARC`
/// table that FreeType does not read.
pub fn outline_collection<'a>(
    font: &FontRef<'a>,
    outlines: Outlines,
) -> Option<OutlineGlyphCollection<'a>> {
    let format = match outlines {
        Outlines::Truetype => OutlineGlyphFormat::Glyf,
        Outlines::Cff => OutlineGlyphFormat::Cff,
        Outlines::Cff2 => OutlineGlyphFormat::Cff2,
        Outlines::None => return None,
    };
    OutlineGlyphCollection::with_format(font, format)
}

fn has_table(font: &FontRef, tag: Tag) -> bool {
    font.table_directory()
        .table_records()
        .iter()
        .any(|record| record.tag() == tag)
}

fn read_info(
    font: &FontRef,
    container: Container,
    index: u32,
    font_count: u32,
    outlines: Outlines,
) -> Result<Info, LoadError> {
    let head = font.head()?;
    let hhea = font.hhea()?;
    let os2 = font.os2().ok();
    let italic = match &os2 {
        Some(os2) => os2
            .fs_selection()
            .contains(read_fonts::tables::os2::SelectionFlags::ITALIC),
        None => head
            .mac_style()
            .contains(read_fonts::tables::head::MacStyle::ITALIC),
    };
    Ok(Info {
        index,
        font_count,
        container,
        outlines,
        family: name(font, NameId::TYPOGRAPHIC_FAMILY_NAME)
            .or_else(|| name(font, NameId::FAMILY_NAME)),
        subfamily: name(font, NameId::TYPOGRAPHIC_SUBFAMILY_NAME)
            .or_else(|| name(font, NameId::SUBFAMILY_NAME)),
        units_per_em: head.units_per_em(),
        ascender: hhea.ascender().to_i16(),
        descender: hhea.descender().to_i16(),
        line_gap: hhea.line_gap().to_i16(),
        weight_class: os2.as_ref().map(|os2| os2.us_weight_class()),
        italic,
        glyph_count: font.maxp()?.num_glyphs(),
        axes: axes(font)?,
    })
}

fn outlines(font: &FontRef) -> Outlines {
    if has_table(font, Tag::new(b"glyf")) {
        Outlines::Truetype
    } else if has_table(font, Tag::new(b"CFF ")) {
        Outlines::Cff
    } else if has_table(font, Tag::new(b"CFF2")) {
        Outlines::Cff2
    } else {
        Outlines::None
    }
}

// A name as fontTools' `getDebugName` chooses it: the first record for the ID in Macintosh
// English or Windows US English, else the last record that decodes.
fn name(font: &FontRef, name_id: NameId) -> Option<String> {
    let table = font.name().ok()?;
    let strings = table.string_data();
    let mut last_decoded = None;
    for record in table.name_record() {
        if record.name_id() != name_id
            || Encoding::new(record.platform_id(), record.encoding_id()) == Encoding::Unknown
        {
            continue;
        }
        let Ok(text) = record.string(strings) else {
            continue;
        };
        let text: String = text.chars().collect();
        if matches!(
            (record.platform_id(), record.language_id()),
            (1, 0) | (3, 0x409)
        ) {
            return Some(text);
        }
        last_decoded = Some(text);
    }
    last_decoded
}

fn axes(font: &FontRef) -> Result<Vec<Axis>, LoadError> {
    if !has_table(font, Tag::new(b"fvar")) {
        return Ok(Vec::new());
    }
    Ok(font
        .fvar()?
        .axes()?
        .iter()
        .map(|axis| Axis {
            tag: axis.axis_tag().to_string(),
            minimum: axis.min_value().to_f64(),
            default: axis.default_value().to_f64(),
            maximum: axis.max_value().to_f64(),
        })
        .collect())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bytes_shorter_than_a_signature_are_an_unknown_format() {
        assert_eq!(decode(b"OT").err(), Some(LoadError::UnknownFormat));
    }

    #[test]
    fn an_unrecognised_signature_is_an_unknown_format() {
        assert_eq!(decode(b"%PDF-1.7").err(), Some(LoadError::UnknownFormat));
    }

    #[test]
    fn an_out_of_bounds_read_is_truncation() {
        assert_eq!(
            LoadError::from(ReadError::OutOfBounds),
            LoadError::Truncated
        );
    }
}
