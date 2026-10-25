---
paths:
  - "lib/pica/native.ex"
  - "native/pica/src/**"
---

# The NIF (`Pica.Native`, `native/pica`)

## Rules

- **Never panic on font data.** No `unwrap`, `expect`, indexing or arithmetic that can panic on
  anything read from a font or passed in by a caller; every failure maps to `{:error, reason}`.
  Rustler turns a panic into a raise, but a panic here is a bug, not an error path.
- **Load checks everything Pica will read, so nothing after it fails on the font's structure.**
  The table directory must hold every record it declares and every table must lie inside the
  data (read-fonts reads as many records as fit, so a cut-off file would otherwise look like one
  missing its tables), the tables Pica reads must be present, and the advance widths and the
  outline table must read. Outlines are read in the format `info/1` reports (skrifa's
  `with_format`), never skrifa's own choice, which prefers an experimental `VARC` table that
  FreeType does not read. Each glyph's data is read only when it is measured, so a malformed
  glyph is an error then, not a panic.
- **The font resource owns its bytes.** A NIF `Binary` is valid only for the call, so a resource
  copies the bytes it keeps, once, at load.
- **Long work runs on a dirty scheduler.** `load` decodes and parses, which can take milliseconds,
  so it is `#[rustler::nif(schedule = "DirtyCpu")]`. A NIF stays on a normal scheduler only when
  measurement shows its typical call well under a millisecond, as the glyph measurements' and
  shaping's do (the numbers are beside them in `lib.rs`); re-measure when one starts doing more per glyph.
- **Measures cross the boundary as lists of tuples, or of structs the user chose.** A map's
  keys are built per glyph, so a measure is a tuple (a glyph's box) unless the user has decided
  its fields are too easy to confuse positionally, as for a shaped glyph, which Rust builds as a
  `%Pica.Glyph{}` (`NifStruct`; design-log §4, "Each shaped glyph is a `%Pica.Glyph{}`").
- **harfrust shapes with the resource's own `harfrust::Font`**, built at load over the same
  bytes, shared rather than copied, so the layout tables harfrust prepares on a font's first
  shaping are kept and reused by every later call; a font harfrust cannot read does not load.
- **No Elixir font parser.** Anything read from a font is read in Rust, through the fontations
  crates and harfrust; the Elixir side wraps, validates options, and names errors.
- **Each stub in `Pica.Native` matches a NIF in `native/pica/src` by name and arity**, and raises
  `:nif_not_loaded` until the library replaces it. The stubs are `@doc false` and not API; the
  public functions over them live in `Pica`.
- **Rust names are descriptive, as Elixir's are**: no abbreviations or single letters
  (`glyph_id`, not `gid`; `position`, not `pos`), crate and library names aside.
