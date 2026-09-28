defmodule Hextank.SettingsTest do
  use ExUnit.Case, async: true

  alias Hextank.Settings

  doctest Hextank.Settings

  test "the defaults are allowed values" do
    assert Settings.validate(Settings.defaults()) == {:ok, Settings.defaults()}
  end

  test "rejects values outside the allowed ones and ignores unknown keys" do
    assert Settings.validate(%{board_radius: 50}) == {:error, :invalid_settings}
    assert Settings.validate(%{obstacle_percent: 7}) == {:error, :invalid_settings}
    assert Settings.validate(%{start_range: 0}) == {:error, :invalid_settings}
    assert Settings.validate(%{colour: :red}) == {:ok, Settings.defaults()}
  end
end
