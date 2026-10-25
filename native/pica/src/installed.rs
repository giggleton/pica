//! Listing installed fonts through fontdb: every face of every font file in the places the
//! platform keeps fonts (on Linux, the directories fontconfig's configuration names), or in one
//! directory the caller gives, with what Pica chooses a face by. Nothing is loaded for measuring
//! here; the caller loads the face it chooses. fontdb skips a file it cannot read, and a face whose
//! file path is not UTF-8 is left out, since the caller reads the file by that path.

use fontdb::{Database, Source, Style};
use rustler::NifMap;

/// One installed face, as `Pica.NearestFace` chooses among them.
#[derive(NifMap)]
pub struct InstalledFace {
    path: String,
    index: u32,
    families: Vec<String>,
    weight: u16,
    italic: bool,
    width: u16,
}

/// Every installed face, or every face in `directory` and the directories beneath it.
pub fn installed_faces(directory: Option<String>) -> Vec<InstalledFace> {
    let mut database = Database::new();
    match directory {
        Some(directory) => database.load_fonts_dir(directory),
        None => database.load_system_fonts(),
    }
    database
        .faces()
        .filter_map(|face| {
            let Source::File(path) = &face.source else {
                return None;
            };
            Some(InstalledFace {
                path: path.to_str()?.to_string(),
                index: face.index,
                families: face
                    .families
                    .iter()
                    .map(|(family, _language)| family.clone())
                    .collect(),
                weight: face.weight.0,
                italic: face.style != Style::Normal,
                width: face.stretch.to_number(),
            })
        })
        .collect()
}
