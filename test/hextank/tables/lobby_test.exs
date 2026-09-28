defmodule Hextank.Tables.LobbyTest do
  use ExUnit.Case, async: true

  alias Hextank.Tables.Lobby

  @now ~U[2026-03-01 12:00:00Z]

  defp days_ago(days), do: DateTime.add(@now, -days * 86_400 - 1, :second)

  describe "expired?/2" do
    test "a finished table is kept for 30 days" do
      refute Lobby.expired?(%{status: :finished, finished_at: days_ago(29)}, @now)
      assert Lobby.expired?(%{status: :finished, finished_at: days_ago(30)}, @now)
    end

    test "a table that never started is kept for 7 days" do
      refute Lobby.expired?(%{status: :lobby, created_at: days_ago(6)}, @now)
      assert Lobby.expired?(%{status: :lobby, created_at: days_ago(7)}, @now)
    end

    test "a running table never expires" do
      refute Lobby.expired?(%{status: :running, created_at: days_ago(365)}, @now)
    end
  end
end
