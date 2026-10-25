defmodule Pica.Glyph do
  @moduledoc """
  One glyph of shaped text, as `Pica.shape/3` returns it. Every length is in font units.

    * `:glyph_id` — which of the font's glyphs it is; 0, `.notdef`, for a character the font
      lacks.
    * `:cluster` — where in the text it came from: the index, counting characters (Unicode code
      points) from 0, of the first character of the cluster it belongs to. A cluster is the
      smallest run of characters and glyphs that shaping keeps together: a ligature for "ffi"
      carries the cluster of its first "f", and an accent joined to its letter carries the
      letter's. Clusters rise along left-to-right text and fall along right-to-left text, since
      glyphs come back in the order they are drawn, from left to right.
    * `:x_advance` — how far the glyph moves the pen on once shaping has positioned it, kerning
      included. A mark that sits on the glyph before it, such as a combining accent, advances 0.
    * `:nominal_advance` — the glyph's advance as the font stores it, before shaping adjusted it,
      as `Pica.nominal_advances/2` gives it. Less `:x_advance`, it is what shaping took off or
      added, such as kerning.
    * `:x_offset`, `:y_offset` — how far the glyph is drawn from where the pen stands, without
      moving the pen, with y rising upward: how an accent is placed over its letter.
  """

  @enforce_keys [:glyph_id, :cluster, :x_advance, :nominal_advance, :x_offset, :y_offset]
  defstruct @enforce_keys

  @typedoc "A shaped glyph."
  @type t :: %__MODULE__{
          glyph_id: non_neg_integer(),
          cluster: non_neg_integer(),
          x_advance: integer(),
          nominal_advance: non_neg_integer(),
          x_offset: integer(),
          y_offset: integer()
        }
end
