# Units and scale

Pica returns the font's own numbers, or HarfBuzz's positions at a scale the caller gives: integers,
but for an outline's coordinates, which are floats as the font's outline draws them. It never
returns points or fractions of its own. This guide is how to turn them into a
size, and why the scale option exists.

## Font units

A font is drawn on a grid of its own, `units_per_em` units to the em, the em being the font size.
Lato has 2000 units per em, so at 12 points one font unit is 12 / 2000 of a point. Everything
`Pica.info/1`, `Pica.nominal_advances/2`, `Pica.glyph_boxes/2`, `Pica.glyph_outlines/2` and,
without `:scale`, `Pica.shape/3` return is in these units. To turn a length into points:

```elixir
points = length * size_in_points / Pica.info(font).units_per_em
```

y rises upward from the baseline: a glyph box's `y_min` is negative where a glyph descends below
it, and `Pica.info/1`'s `descender` is negative.

## What a shaped glyph's numbers mean

Each `Pica.Glyph` carries two advances. `nominal_advance` is the glyph's advance as the font stores
it; `x_advance` is how far it moves the pen once shaping has positioned it. Their difference is
what shaping added or took away, mostly kerning:

```elixir
{:ok, font} = Pica.lookup("Lato")
[a, v] = Pica.shape(font, "AV")
a.x_advance - a.nominal_advance
#=> -108, Lato's kerning for "AV", in font units
```

A string's width is the sum of its glyphs' `x_advance`. `x_offset` and `y_offset` move where a
glyph is drawn without moving the pen, which is how an accent sits over its letter.

## Why the scale option exists

Turning font units into a size rounds them, and where the rounding happens changes the total. A
renderer working at a size positions each glyph at that size and rounds each one, so the width
it draws is a sum of rounded advances, not the rounded sum of exact ones. Rounding Pica's font
units yourself cannot reproduce it.

With `:scale`, shaping itself works at the scale: the em is divided into that many units, and
each glyph's advance and offset is rounded to a whole unit as HarfBuzz rounds it. At 12 points,
`scale: 12 * 64` gives every length in 1/64 point, the grid FreeType and many renderers use:

```elixir
width_in_64ths =
  font
  |> Pica.shape("AV", scale: 12 * 64)
  |> Enum.map(fn glyph -> glyph.x_advance end)
  |> Enum.sum()

width_in_points = width_in_64ths / 64
#=> 15.609375 for Lato Regular
```

## HarfBuzz's rounding, not FreeType's

Pica rounds as HarfBuzz does with its own font functions. A renderer whose HarfBuzz takes each
glyph's advance from FreeType, as R's svglite does, rounds by FreeType's arithmetic instead, and
some glyphs come out a unit wider: at 12 points in 64ths, about one glyph in ten in Lato, and up to
six 64ths of a point over a label such as "Average Temperature, °F". To compare Pica's widths
with such a renderer's, allow a tolerance of a few units at the scale.
