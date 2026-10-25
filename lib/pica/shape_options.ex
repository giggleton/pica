defmodule Pica.ShapeOptions do
  @moduledoc false

  # The checks NimbleOptions runs on `Pica.shape/3`'s `:features`, `:script` and `:language`, as
  # `{:custom, Pica.ShapeOptions, check, []}` types in its schema, which `Pica` holds with the
  # options' documentation. Each check refuses a value that is not of the option's form, with a
  # message saying what the form is, and returns a value it accepts as the NIF takes it: features
  # as `{tag, value}`, the tag a four-byte string and `true` and `false` as 1 and 0. A value of the
  # right form passes whether or not the font or Unicode knows it, as HarfBuzz lets it pass: a
  # feature the font lacks does nothing, an unknown script shapes with HarfBuzz's default shaper,
  # and a language the font has no rules for changes nothing.

  @largest_feature_value 0xFFFFFFFF

  defguardp is_printable(byte) when byte in 0x20..0x7E
  defguardp is_letter(byte) when byte in ?a..?z or byte in ?A..?Z
  defguardp is_language_byte(byte) when is_letter(byte) or byte in ?0..?9 or byte in [?-, ?_]

  defguardp is_feature_value(value)
            when is_boolean(value) or
                   (is_integer(value) and value >= 0 and value <= @largest_feature_value)

  @doc false
  # Features as a keyword list of four-character tags and values, in the NIF's form.
  @spec features(term()) :: {:ok, [{String.t(), non_neg_integer()}]} | {:error, String.t()}
  def features(features) when is_list(features), do: feature_settings(features, [])

  def features(not_a_list) do
    {:error, "expected a keyword list of feature tags and values, got: #{inspect(not_a_list)}"}
  end

  @doc false
  # A script as its four-letter ISO 15924 code, in any case.
  @spec script(term()) :: {:ok, String.t()} | {:error, String.t()}
  def script(<<first, second, third, fourth>> = script)
      when is_letter(first) and is_letter(second) and is_letter(third) and is_letter(fourth) do
    {:ok, script}
  end

  def script(not_a_script) do
    {:error,
     "expected a script as its four-letter ISO 15924 code, such as \"Latn\", got: " <>
       inspect(not_a_script)}
  end

  @doc false
  # A language as a BCP 47 tag: letters, digits, `-` and `_`.
  @spec language(term()) :: {:ok, String.t()} | {:error, String.t()}
  def language(language) when is_binary(language) and byte_size(language) > 0 do
    if language_tag?(language), do: {:ok, language}, else: language_error(language)
  end

  def language(not_a_language), do: language_error(not_a_language)

  defp feature_settings([], settings), do: {:ok, Enum.reverse(settings)}

  defp feature_settings([{tag, value} | features], settings)
       when is_atom(tag) and is_feature_value(value) do
    case Atom.to_string(tag) do
      <<first, second, third, fourth>> = tag_string
      when is_printable(first) and is_printable(second) and is_printable(third) and
             is_printable(fourth) ->
        feature_settings(features, [{tag_string, feature_value(value)} | settings])

      _not_a_tag ->
        {:error,
         "expected feature tags of four printable ASCII characters, such as :kern, got: " <>
           inspect(tag)}
    end
  end

  defp feature_settings([not_a_feature | _features], _settings) do
    {:error,
     "expected each feature as tag: value, the value true, false or an integer from 0 to " <>
       "#{@largest_feature_value}, got: #{inspect(not_a_feature)}"}
  end

  defp feature_value(true), do: 1
  defp feature_value(false), do: 0
  defp feature_value(value), do: value

  defp language_tag?(<<>>), do: true
  defp language_tag?(<<byte, rest::binary>>) when is_language_byte(byte), do: language_tag?(rest)
  defp language_tag?(_not_a_tag), do: false

  defp language_error(not_a_language) do
    {:error,
     "expected a language as a BCP 47 tag of letters, digits, - and _, such as \"tr\" or " <>
       "\"sr-Cyrl\", got: #{inspect(not_a_language)}"}
  end
end
