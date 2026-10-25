---
paths:
  - "lib/pica.ex"
  - "lib/pica/font.ex"
---

# The public API (`Pica`)

## Rules

- **Pica knows nothing of its consumers.** Giggly is the first, and it depends on Pica
  optionally, compiling its adapter behind `Code.ensure_loaded?(Pica)`; so Pica never depends on
  Giggly, names it in code, or shapes its API around it.
- **A name looks in the fonts the app gave Pica first, then the installed fonts.** Given fonts
  always win; the installed fonts are a fallback, on unless a lookup passes `installed: false`
  (design-log §4, the entries beginning "A name finds the fonts the app gave Pica first" and "An
  app opts out"). No global switch records the choice.
- **Each face is looked up on its own.** A face the app did not give falls through to the
  installed fonts, even when the app gave another face of that family; the regular face never
  stands in for a missing bold.
- **Pica never substitutes a font.** Names match exactly. A family found in neither place is
  `:error`, and a character the font lacks shapes to glyph 0 with its cluster.
- **Generic names are ordinary names.** `""`, `"sans"`, `"serif"` and `"mono"` are never
  aliased to another family; they resolve only to a font whose family is exactly that name.
- **Pica returns the font's numbers and HarfBuzz's positions, nothing more.** Rounding to a
  caller's grid, a line's ascent or descent, what a missing character measures: those are the
  caller's rules (Giggly keeps R's), never Pica's.
- **Numbers are font units, or HarfBuzz-scaled with `scale:`.** Pica never returns points or
  floats it computed itself; scaling and rounding happen inside shaping, per glyph, as HarfBuzz
  does them.
- **Shaping defaults are HarfBuzz's.** The features HarfBuzz enables for the script are on, and
  direction and script are guessed from the text, unless a call overrides them.
- **A loaded font is a `Pica.Font`, read through Pica's functions.** The struct is opaque; its
  information is read once, at load, so `Pica.info/1` never fails and never calls the NIF.
- **`info/1` reports the font's own numbers**: the `hhea` line metrics as the table gives them,
  the names as fontTools' `getDebugName` chooses them, and `:none` for a value the font lacks.
- **The API raises on misuse.** Options are validated with NimbleOptions; a font Pica cannot read
  raises `ArgumentError` naming the problem where the function promises bytes it can read, and
  returns `{:error, reason}` where it promises to try.
