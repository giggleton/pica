# Pica

Text shaping and font metrics for Elixir, through [harfrust](https://github.com/harfbuzz/harfrust),
HarfBuzz's Rust port.

Pica measures text from font files. Register font files under a family name, then ask, by family
and face, for each string's glyphs: which glyph, which characters it came from, and how far it
advances with kerning, ligatures and contextual forms applied. It also reports font-wide metrics
and glyph bounding boxes. Nothing is drawn.

**Status:** in development; the API is not built yet.

## Building from source

Pica ships prebuilt binaries through
[`rustler_precompiled`](https://hex.pm/packages/rustler_precompiled), so using a release needs no
Rust. A development version (`-dev`), or `PICA_BUILD=1`, builds the NIF from source, which needs a
Rust toolchain at least as new as `rust-version` in `native/pica/Cargo.toml`.

## Licence

MIT; see [LICENSE](LICENSE).
