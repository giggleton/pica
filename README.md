# Pica

Text shaping and font metrics for Elixir, through [harfrust](https://github.com/harfbuzz/harfrust),
HarfBuzz's Rust port.

Pica measures text from font files. Register fonts under a family name, then ask, by family and
face, for each string's glyphs: which glyph, which characters it came from, and how far it
advances with kerning, ligatures and contextual forms applied. It also reports font-wide metrics,
glyph bounding boxes, and glyph outlines as drawing commands. Nothing is rendered.

```elixir
{:ok, font} = Pica.load(File.read!("Lato-Regular.ttf"))
:ok = Pica.register("Lato", plain: font)

{:ok, font} = Pica.lookup("Lato")
Pica.shape(font, "AV", scale: 12 * 64)
#=> [%Pica.Glyph{glyph_id: 3, cluster: 0, x_advance: 479, ...}, %Pica.Glyph{...}]
```

## Installation

```elixir
def deps do
  [{:pica, "~> 0.1"}]
end
```

Pica ships prebuilt binaries through
[`rustler_precompiled`](https://hex.pm/packages/rustler_precompiled), so using a release needs no
Rust.

## Documentation

- The `Pica` module documentation: loading, fonts by name, glyphs, shaping and scale.
- [Registering fonts](guides/registering-fonts.md): in an application and in Livebook.
- [Units and scale](guides/units.md): what the numbers are, and turning them into a size.

## Building from source

A development version (`-dev`), or `PICA_BUILD=1`, builds the NIF from source, which needs a
Rust toolchain at least as new as `rust-version` in `native/pica/Cargo.toml`. Releases follow
[RELEASE.md](https://github.com/giggleton/pica/blob/main/RELEASE.md).

## Licence

MIT; see [LICENSE](LICENSE). The Rust crates compiled into the NIF are listed, with their
licences, in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
