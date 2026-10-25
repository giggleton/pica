defmodule Pica.RegistryTest do
  # Every test registers families under names of its own, so the tests share the VM's
  # `:persistent_term` table without seeing each other's families, and run async.
  use ExUnit.Case, async: true

  @fonts "test/fonts"

  setup context do
    family = "Pica registry test: #{context.test}"
    on_exit(fn -> Pica.unregister(family) end)
    %{family: family, regular: load_font("Lato-Regular.ttf"), bold: load_font("Lato-Bold.ttf")}
  end

  describe "a registered family" do
    test "answers each face it was given with that font", context do
      :ok = Pica.register(context.family, plain: context.regular, bold: context.bold)

      assert Pica.lookup(context.family, :plain) == {:ok, context.regular}
      assert Pica.lookup(context.family, :bold) == {:ok, context.bold}
    end

    test "is its plain face when no face is asked for, with or without options", context do
      :ok = Pica.register(context.family, plain: context.regular)

      assert Pica.lookup(context.family) == {:ok, context.regular}
      assert Pica.lookup(context.family, installed: false) == {:ok, context.regular}
    end

    test "never answers a face it lacks with another of its faces", context do
      :ok = Pica.register(context.family, plain: context.regular)

      for face <- [:bold, :italic, :bold_italic] do
        assert Pica.lookup(context.family, face, installed: false) == :error
      end
    end

    test "is replaced whole by registering it again", context do
      :ok = Pica.register(context.family, plain: context.regular, bold: context.bold)
      :ok = Pica.register(context.family, plain: context.bold)

      assert Pica.lookup(context.family, :plain) == {:ok, context.bold}
      assert Pica.lookup(context.family, :bold, installed: false) == :error
    end

    test "is listed and registered until it is unregistered", context do
      :ok = Pica.register(context.family, plain: context.regular)
      assert Pica.registered?(context.family)
      assert context.family in Pica.families()

      assert Pica.unregister(context.family) == :ok
      refute Pica.registered?(context.family)
      refute context.family in Pica.families()
      assert Pica.lookup(context.family, installed: false) == :error
    end

    test "may be named anything, its fonts' own family names aside", context do
      :ok = Pica.register(context.family, plain: context.regular)
      {:ok, font} = Pica.lookup(context.family)
      assert Pica.info(font).family == "Lato"
    end
  end

  test "unregistering a family never registered is :ok", %{family: family} do
    assert Pica.unregister(family) == :ok
  end

  test "the families are sorted", %{family: family, regular: regular} do
    for name <- ["#{family} b", "#{family} a"] do
      :ok = Pica.register(name, plain: regular)
      on_exit(fn -> Pica.unregister(name) end)
    end

    ours = Enum.filter(Pica.families(), fn name -> String.starts_with?(name, family) end)
    assert ours == ["#{family} a", "#{family} b"]
  end

  # The family is found nowhere, so this reads the machine's installed fonts and finds no face:
  # the wiring of installed: true, whatever fonts the machine has.
  test "a family neither registered nor installed has no face", %{family: family} do
    assert Pica.lookup(family, :plain) == :error
  end

  describe "misuse" do
    test "a face that is not a loaded font is refused, naming it", %{family: family} do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Pica.register(family, plain: "not a font")
        end

      assert error.message =~ ":plain"
      refute Pica.registered?(family)
    end

    test "a face Pica does not have is refused, naming it", context do
      assert_raise NimbleOptions.ValidationError, ~r/:semibold/, fn ->
        Pica.register(context.family, semibold: context.bold)
      end

      error = assert_raise ArgumentError, fn -> Pica.lookup(context.family, :semibold) end
      assert error.message =~ inspect(:semibold)
    end

    test "registering no faces is refused, naming the family", %{family: family} do
      error = assert_raise ArgumentError, fn -> Pica.register(family, []) end
      assert error.message =~ inspect(family)
    end

    test "an installed: that is not a boolean is refused, naming it", %{family: family} do
      error =
        assert_raise NimbleOptions.ValidationError, fn ->
          Pica.lookup(family, :plain, installed: "no")
        end

      assert error.message =~ ":installed"
    end
  end

  defp load_font(file) do
    {:ok, font} =
      @fonts
      |> Path.join(file)
      |> File.read!()
      |> Pica.load()

    font
  end
end
