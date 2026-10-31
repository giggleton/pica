# Registering fonts

Pica finds fonts by family name. A name is looked up first among the fonts the application
registered, then among the fonts installed on the machine. Registering is how an application
pins the exact font files it measures with, whatever the machine has.

## In an application

Register fonts once, when the application starts. Pica keeps registered fonts in
`:persistent_term`, where reading them from any process costs nothing, but registering a family
again or unregistering one makes every process in the VM garbage collect. That suits startup, not
a request handler.

Ship the font files in `priv/` and register them in the application's `start/2` callback, before
the supervision tree starts anything that measures text:

```elixir
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    register_fonts()

    children = [
      # ...
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)
  end

  defp register_fonts do
    :ok = Pica.register("Lato", plain: font("Lato-Regular.ttf"), bold: font("Lato-Bold.ttf"))
  end

  defp font(file) do
    {:ok, font} =
      :my_app
      |> Application.app_dir(Path.join("priv/fonts", file))
      |> File.read!()
      |> Pica.load()

    font
  end
end
```

`Pica.load/2` returns `{:error, reason}` for bytes it cannot read; matching on `{:ok, font}` at
startup makes a missing or corrupt font file stop the application with the reason, rather than
surface later as a failed lookup.

Anywhere in the application afterwards:

```elixir
{:ok, font} = Pica.lookup("Lato", :bold)
glyphs = Pica.shape(font, "Average Temperature, °F", scale: 12 * 64)
```

### Faces and the installed fonts

A family has up to four faces: `:plain`, `:bold`, `:italic` and `:bold_italic`. A face the
application did not register is looked for among the installed fonts, never answered with another
registered face: when only Lato's plain face is registered, `Pica.lookup("Lato", :bold)` finds an
installed Lato bold if the machine has one, and is `:error` if not.

To measure only with the fonts the application ships, so results never depend on the machine,
pass `installed: false`:

```elixir
Pica.lookup("Lato", :italic, installed: false)
#=> :error
```

The first lookup that reaches the installed fonts reads every font file on the machine, which can
take a second or more, and its result is kept for the life of the VM. An application that relies
on installed fonts can make that first lookup at startup too.

### The name is yours

The name a family is registered under need not be the font's own family name. An application can
register `"Body"` and `"Headings"`, or keep two versions of a font apart. `Pica.info/1` still
reports the font's own names. Registering a name again replaces the whole family: faces given
before and not given now are no longer registered.

## In Livebook

Install Pica in the notebook's setup cell, then load and register fonts in a cell of their own:

```elixir
Mix.install([{:pica, "~> 0.1"}])
```

```elixir
load = fn path ->
  {:ok, font} = path |> File.read!() |> Pica.load()
  font
end

:ok = Pica.register("Lato", plain: load.("/data/fonts/Lato-Regular.ttf"))
```

Running the cell again re-registers the family, which is harmless in a notebook. A notebook can
also skip registering and look up a family the machine has installed:

```elixir
{:ok, font} = Pica.lookup("DejaVu Sans")
```

Or skip names altogether and measure with a font it has just loaded, since every measuring
function takes a loaded font:

```elixir
font = load.("/data/fonts/Lato-Regular.ttf")
Pica.shape(font, "Office affiliation")
```
