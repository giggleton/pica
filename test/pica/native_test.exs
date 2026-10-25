defmodule Pica.NativeTest do
  use ExUnit.Case, async: true

  alias Pica.Native

  test "the NIF library loads and answers" do
    # The stub raises, so any answer at all means the Rust library replaced it. The form is
    # asserted rather than the number, which moves with every bump of native/pica/Cargo.toml.
    assert Native.crate_version() =~ ~r/\A\d+\.\d+\.\d+\z/
  end
end
