defmodule Pica do
  @moduledoc """
  Text shaping and font metrics for Elixir, through HarfBuzz's Rust port.

  Pica measures text from font files. A caller registers font files under a family name, then
  asks, by family and face, for each string's glyphs: which glyph, which characters it came from,
  how far it advances once kerning, ligatures and contextual forms are applied, and how far it
  would advance unshaped. It also reports font-wide metrics and glyph bounding boxes. Nothing is
  drawn.

  A family name is looked up first among the fonts given to Pica, then, unless the caller opts
  out, among the fonts installed on the machine. Pica never substitutes one font for another:
  names match exactly, a family found in neither place is an error, and a character the font
  lacks shapes to glyph 0.

  The API is not built yet; `notes/design-log.md` records the plan.
  """

  # The root boundary. It lists every outside library a sub-boundary does, since a sub-boundary
  # may list only what its parent lists (`.claude/rules/dependencies.md`).
  use Boundary,
    deps: [{Mix, :compile}, {Rustler, :compile}, {RustlerPrecompiled, :compile}],
    exports: []
end
