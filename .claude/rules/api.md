---
paths:
  - "lib/pica.ex"
  - "lib/pica/font.ex"
  - "lib/pica/fonts.ex"
  - "lib/pica/glyph.ex"
  - "lib/pica/nearest_face.ex"
  - "lib/pica/shape_options.ex"
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
- **`register/2` files loaded fonts under the app's name for them**, never bytes, and never checks
  the name against a font's own family; registering a family again replaces it whole
  (design-log §4, "`register/2` takes loaded fonts", "A registered name is the app's label",
  "Registering a family again replaces it whole").
- **An installed face is the nearest of its kind, never another kind.** A family name matches one
  of the font's family names exactly; plain is upright and below 600, bold upright and 600 or
  above, italic and bold italic italic or oblique; the nearest weight wins, then the width nearest
  normal, then path and index. `Pica.NearestFace` holds the rule as a pure fold, so the registry
  module is the only impure one (design-log §4, "An installed face is the nearest of its kind").
- **Each face is looked up on its own.** A face the app did not give falls through to the
  installed fonts, even when the app gave another face of that family; the regular face never
  stands in for a missing bold.
- **Pica never substitutes a font.** Names match exactly. A family found in neither place is
  `:error`, and a character the font lacks shapes to glyph 0 with its cluster. A character
  Unicode marks as default-ignorable, such as a soft hyphen or a zero-width joiner, is hidden as
  HarfBuzz hides it, whether or not the font has it: the font's space glyph, advancing 0, or no
  glyph at all in a font without a space.
- **Generic names are ordinary names.** `""`, `"sans"`, `"serif"` and `"mono"` are never
  aliased to another family; they resolve only to a font whose family is exactly that name.
- **Pica returns the font's numbers and HarfBuzz's positions, nothing more.** Rounding to a
  caller's grid, a line's ascent or descent, what a missing character measures: those are the
  caller's rules (Giggly keeps R's), never Pica's.
- **Numbers are font units, or HarfBuzz-scaled with `scale:`.** Pica never returns points or
  floats it computed itself; scaling and rounding happen inside shaping, per glyph, as HarfBuzz
  does them, nominal advances included. Outlines are floats, the font's points as skrifa draws
  them (design-log §4, "An outline's coordinates are always floats"). The rounding is
  HarfBuzz's own, never FreeType's: a renderer whose HarfBuzz takes advances from FreeType, as
  svglite's does, can differ by a unit per glyph, and matching it is the caller's tolerance, not
  Pica's code (design-log §4, "Pica rounds as HarfBuzz does, not as FreeType does").
- **Shaping defaults are HarfBuzz's.** The features HarfBuzz enables for the script are on, and
  direction and script are guessed from the text, unless a call overrides them. The language is
  none unless a call gives one: Pica never reads the machine's locale, as C HarfBuzz does.
- **`shape/3` shapes one string into `%Pica.Glyph{}`s, in the order they are drawn**, left to
  right on the page for right-to-left text too, each cluster the index of a code point counting
  from 0, as hb-shape's are (design-log §4, "`shape/3` shapes one string", "Each shaped glyph is
  a `%Pica.Glyph{}`", "Clusters count characters").
- **Shaping's options are checked for their form, never their meaning.** A feature tag that is
  not four printable ASCII characters, a feature value that is not a boolean or a 32-bit natural
  number, a vertical or unknown direction, a script that is not four letters, or a language tag
  of anything but letters, digits, `-` and `_` raises `NimbleOptions.ValidationError`; a value of
  the right form passes whether or not the font or Unicode knows it, and does what HarfBuzz does
  with it (design-log §4, "Shaping's options take HarfBuzz's forms").
- **A loaded font is a `Pica.Font`, read through Pica's functions.** The struct is opaque; its
  information is read once, at load, so `Pica.info/1` never fails and never calls the NIF.
- **`info/1` reports the font's own numbers**: the `hhea` line metrics as the table gives them,
  the names as fontTools' `getDebugName` chooses them, and `:none` for a value the font lacks.
- **Glyphs are measured by glyph id, at the font's default location.** `nominal_advances/2`,
  `glyph_boxes/2` and `glyph_outlines/2` take ids, as shaping returns them; `glyph_ids/2` is the
  font's character map alone, one id per code point, 0 for a character the font lacks, never a
  shaped result (design-log §4, "Glyphs are measured by glyph id").
- **A glyph's box is its outline's control box, never the box the font stores**: every point,
  on and off the curve, as FreeType computes it unscaled, in whole font units. A glyph with no
  outline has no box, `:none`, never zeros; what such a glyph measures is the caller's rule
  (design-log §4, "A glyph's box is its outline's control box", "A glyph with no outline").
- **A glyph's outline is what skrifa draws, in FreeType's path style**: unscaled and unhinted, a
  contour that begins off the curve started where FreeType starts it, as flat tuples in one list
  per glyph, with no `:line` back to the start before a `:close`. A glyph that draws nothing is
  `:none`, and so is every glyph of a font with no outlines (design-log §4, "`glyph_outlines/2`
  draws each glyph as skrifa draws it", "Outline commands are flat tuples").
- **A glyph id the font lacks raises `ArgumentError`** naming the font's last glyph id, checked
  in Elixir against `glyph_count` before the NIF is called; so does a glyph whose data does not
  read.
- **The API raises on misuse.** Options are validated with NimbleOptions; a font Pica cannot read
  raises `ArgumentError` naming the problem where the function promises bytes it can read, and
  returns `{:error, reason}` where it promises to try.
