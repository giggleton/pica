defmodule Pica.ShapeOptionsTest do
  use ExUnit.Case, async: true

  alias Pica.ShapeOptions

  describe "features/1" do
    test "a keyword list becomes four-byte tags, with true and false as 1 and 0" do
      assert ShapeOptions.features(kern: false, liga: true, salt: 2) ==
               {:ok, [{"kern", 0}, {"liga", 1}, {"salt", 2}]}
    end

    test "a tag of four printable ASCII characters passes, spaces included" do
      assert ShapeOptions.features([{:"cv1 ", true}]) == {:ok, [{"cv1 ", 1}]}
    end

    test "values from 0 to the largest 32-bit number pass" do
      assert ShapeOptions.features(salt: 0, aalt: 0xFFFFFFFF) ==
               {:ok, [{"salt", 0}, {"aalt", 0xFFFFFFFF}]}
    end

    test "a tag not of four printable ASCII characters is refused, naming it" do
      for tag <- [:kerning, :ker, :kérn, :"ke\nn"] do
        assert {:error, message} = ShapeOptions.features([{tag, true}])
        assert message =~ inspect(tag)
      end
    end

    test "a value not a boolean or a 32-bit natural number is refused, naming the feature" do
      for value <- [-1, 0x100000000, :on, 1.0, "1", nil] do
        assert {:error, message} = ShapeOptions.features(kern: value)
        assert message =~ inspect({:kern, value})
      end
    end

    test "a feature not written as tag: value is refused, naming it" do
      for not_a_feature <- [{"kern", true}, :kern, {:kern, true, 0}] do
        assert {:error, message} = ShapeOptions.features([not_a_feature])
        assert message =~ inspect(not_a_feature)
      end
    end

    test "features not in a list are refused, naming them" do
      assert {:error, message} = ShapeOptions.features(%{kern: false})
      assert message =~ inspect(%{kern: false})
    end
  end

  describe "script/1" do
    test "four ASCII letters pass in any case, whether or not they name a script" do
      for script <- ["Latn", "arab", "HEBR", "Abcd"] do
        assert ShapeOptions.script(script) == {:ok, script}
      end
    end

    test "anything else is refused, naming it" do
      for not_a_script <- ["Arabic", "Ara", "", "Ar1b", "Arä", :arab, nil] do
        assert {:error, message} = ShapeOptions.script(not_a_script)
        assert message =~ inspect(not_a_script)
      end
    end
  end

  describe "language/1" do
    test "letters, digits, - and _ pass, whether or not they name a language" do
      for language <- ["tr", "sr-Cyrl", "en_US", "es-419", "xx"] do
        assert ShapeOptions.language(language) == {:ok, language}
      end
    end

    test "anything else is refused, naming it" do
      for not_a_language <- ["", "en US", "fr.UTF-8", "é", :tr, nil] do
        assert {:error, message} = ShapeOptions.language(not_a_language)
        assert message =~ inspect(not_a_language)
      end
    end
  end
end
