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
  missing its tables), and the tables Pica reads must be present.
- **The font resource owns its bytes.** A NIF `Binary` is valid only for the call, so a resource
  copies the bytes it keeps, once, at load.
- **Long work runs on a dirty scheduler.** `load` decodes and parses, which can take milliseconds,
  so it is `#[rustler::nif(schedule = "DirtyCpu")]`. A NIF stays on a normal scheduler only when
  measurement shows its typical call well under a millisecond.
- **Batches cross the boundary as tuples and lists, not maps.** A caller measures many strings in
  one call, and every map key is built and read per glyph.
- **No Elixir font parser.** Anything read from a font is read in Rust, through the fontations
  crates and harfrust; the Elixir side wraps, validates options, and names errors.
- **Each stub in `Pica.Native` matches a NIF in `native/pica/src` by name and arity**, and raises
  `:nif_not_loaded` until the library replaces it. The stubs are `@doc false` and not API; the
  public functions over them live in `Pica`.
- **Rust names are descriptive, as Elixir's are**: no abbreviations or single letters
  (`glyph_id`, not `gid`; `position`, not `pos`), crate and library names aside.
