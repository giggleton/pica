# Measures drawing glyph outlines, to choose the NIF's scheduler as `.claude/rules/native.md` asks:
# a label's glyphs, a hundred glyphs, and every glyph of the font, in TrueType (Lato, and Lobster,
# whose curves have many points) and CFF (Source Serif). Glyph boxes, which draw the same outlines
# into a box, are measured beside them, and choose their scheduler by the same count. Run from the
# repository root:
#
#   mix run bench/glyph_outlines.exs
#
# Benchee runs only in dev, so this is never part of the test suite or the quality gate.

fonts = "test/fonts"

load = fn file ->
  {:ok, font} = Pica.load(File.read!(Path.join(fonts, file)))
  font
end

label = "Highway miles per gallon"

cases =
  for {name, file} <- [
        {"Lato", "Lato-Regular.ttf"},
        {"Lobster", "Lobster-Regular.ttf"},
        {"Source Serif", "SourceSerif4-Regular.otf"}
      ],
      reduce: %{} do
    cases ->
      font = load.(file)
      every_glyph = Enum.to_list(0..(Pica.info(font).glyph_count - 1))
      label_glyphs = Pica.glyph_ids(font, label)
      hundred_glyphs = Enum.take(every_glyph, 100)

      Map.merge(cases, %{
        "#{name}: outlines, a label (#{length(label_glyphs)} glyphs)" => fn ->
          Pica.glyph_outlines(font, label_glyphs)
        end,
        "#{name}: outlines, 100 glyphs" => fn -> Pica.glyph_outlines(font, hundred_glyphs) end,
        "#{name}: outlines, every glyph (#{length(every_glyph)})" => fn ->
          Pica.glyph_outlines(font, every_glyph)
        end,
        "#{name}: boxes, 100 glyphs" => fn -> Pica.glyph_boxes(font, hundred_glyphs) end,
        "#{name}: boxes, every glyph (#{length(every_glyph)})" => fn ->
          Pica.glyph_boxes(font, every_glyph)
        end
      })
  end

Benchee.run(cases, warmup: 1, time: 3, print: [configuration: false])
