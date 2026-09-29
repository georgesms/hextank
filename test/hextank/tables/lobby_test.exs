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

    test "a running table is deleted once every living tank has more than 200 AP" do
      # Started 100 minutes ago with 1 AP per minute, and asleep since the start: the
      # 100 missed ticks count as AP too.
      asleep = %{
        status: :running,
        created_at: days_ago(365),
        started_at: DateTime.add(@now, -100 * 60, :second),
        tick_interval: 60,
        ticks: 0,
        lowest_ap: 0
      }

      refute Lobby.expired?(%{asleep | lowest_ap: 100}, @now)
      assert Lobby.expired?(%{asleep | lowest_ap: 101}, @now)

      # Saved just now, with every tick already handed out.
      awake = %{asleep | ticks: 100}
      refute Lobby.expired?(%{awake | lowest_ap: 200}, @now)
      assert Lobby.expired?(%{awake | lowest_ap: 201}, @now)
    end
  end
end
