defmodule Pica.Font do
  @moduledoc """
  A loaded font, as `Pica.load/2` returns it.

  The struct is opaque: pass it back to Pica's functions, and read what it holds through them,
  such as `Pica.info/1`. It keeps the font's decoded bytes in native memory, outside the
  process heap, and its information, read once when it was loaded.
  """

  @enforce_keys [:resource, :info]
  defstruct [:resource, :info]

  @typedoc "A loaded font."
  @opaque t :: %__MODULE__{resource: reference(), info: Pica.info()}

  @doc false
  # Builds the struct from what `Pica.Native.load/2` returns, turning the absent values Rust
  # sends as `nil` into `:none`.
  @spec new(reference(), map()) :: t()
  def new(resource, info) when is_reference(resource) and is_map(info) do
    %__MODULE__{
      resource: resource,
      info: %{
        info
        | family: none_if_nil(info.family),
          subfamily: none_if_nil(info.subfamily),
          weight_class: none_if_nil(info.weight_class)
      }
    }
  end

  @doc false
  # The font's information, for `Pica.info/1`.
  @spec info(t()) :: Pica.info()
  def info(%__MODULE__{info: info}), do: info

  @doc false
  # The native resource holding the font, for the NIF calls in `Pica`.
  @spec resource(t()) :: reference()
  def resource(%__MODULE__{resource: resource}), do: resource

  defp none_if_nil(nil), do: :none
  defp none_if_nil(value), do: value
end
