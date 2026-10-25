# Measures loading and shaping, as step 9 of the plan asks: loading Lato and Roboto, and shaping a
# batch of 100 short labels, the axis labels of a plot, one call per label. The target is a batch
# well under a millisecond once the font is loaded. Run from the repository root:
#
#   mix run bench/shaping.exs
#
# Benchee runs only in dev, so this is never part of the test suite or the quality gate.

fonts = "test/fonts"
read = fn file -> File.read!(Path.join(fonts, file)) end
lato_bytes = read.("Lato-Regular.ttf")
roboto_bytes = read.("Roboto[wdth,wght].ttf")
{:ok, lato} = Pica.load(lato_bytes)
{:ok, roboto} = Pica.load(roboto_bytes)

# A plot's labels: titles, words and numbers, a hundred of them.
words = [
  "Average Temperature, °F",
  "Highway miles per gallon",
  "Fuel efficiency (mpg)",
  "Weight (1000 lbs)",
  "Office affiliation"
]

labels =
  Enum.map(1..100, fn number ->
    if rem(number, 2) == 0, do: Integer.to_string(number * 25), else: Enum.at(words, rem(number, 5))
  end)

shape_all = fn font, options ->
  Enum.each(labels, fn label -> Pica.shape(font, label, options) end)
end

Benchee.run(
  %{
    "load Lato" => fn -> Pica.load(lato_bytes) end,
    "load Roboto" => fn -> Pica.load(roboto_bytes) end
  },
  warmup: 1,
  time: 3,
  print: [configuration: false]
)

Benchee.run(
  %{
    "100 labels, Lato" => fn -> shape_all.(lato, []) end,
    "100 labels, Lato, scale 768" => fn -> shape_all.(lato, scale: 768) end,
    "100 labels, Lato, kerning off" => fn -> shape_all.(lato, features: [kern: false]) end,
    "100 labels, Roboto" => fn -> shape_all.(roboto, []) end
  },
  warmup: 1,
  time: 3,
  print: [configuration: false]
)
