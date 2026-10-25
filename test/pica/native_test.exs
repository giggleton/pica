defmodule Pica.NativeTest do
  use ExUnit.Case, async: true

  alias Pica.Native

  test "the NIF library loads and answers" do
    # The stub raises, so any answer at all means the Rust library replaced it. The form is
    # asserted rather than the number, which moves with every bump of native/pica/Cargo.toml.
    assert Native.crate_version() =~ ~r/\A\d+\.\d+\.\d+\z/
  end

  # Golden: test/fixtures/font_info.exs is fontTools' reading of each test font (its header names
  # the version): the family as name ID 16, else 1, the OS/2 weight class and the italic bit. A
  # changed test font or a regenerated fixture moves it; nothing in Pica does. fontdb lists
  # neither a WOFF nor a font with no family name, which leaves out the WOFF and WOFF2 files and
  # Roboto-Bare.ttf.
  @fixture "test/fixtures/font_info.exs"
  @external_resource @fixture
  {expected_info, _bindings} = Code.eval_file(@fixture)

  @expected_faces expected_info
                  |> Enum.reject(fn info ->
                    info.container in [:woff, :woff2] or info.family == :none
                  end)
                  |> Enum.map(fn info ->
                    {info.file, info.index, info.family, info.weight_class, info.italic}
                  end)
                  |> Enum.sort()

  test "installed_faces/1 lists each face in a directory as fontTools reads it" do
    faces =
      "test/fonts"
      |> Native.installed_faces()
      |> Enum.map(fn face ->
        {Path.basename(face.path), face.index, hd(face.families), face.weight, face.italic}
      end)
      |> Enum.sort()

    assert faces == @expected_faces
  end
end
