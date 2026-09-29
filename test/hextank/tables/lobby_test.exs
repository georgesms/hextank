defmodule Hextank.Tables.LobbyTest do
  use ExUnit.Case, async: true

  alias Hextank.Game
  alias Hextank.Tables.Lobby

  @now ~U[2026-03-01 12:00:00Z]

  defp new_game do
    Game.new(
      id: "t1",
      name: "Test",
      visibility: :public,
      creator_id: "ana",
      tick_interval: 60,
      created_at: @now
    )
  end

  defp days_ago(days), do: DateTime.add(@now, -days * 86_400 - 1, :second)

  describe "summary/1" do
    test "counts the living tanks and names the winner" do
      {:ok, game} = Game.add_player(new_game(), "ana", "Ana", @now)
      {:ok, game} = Game.add_player(game, "bruno", "Bruno", @now)
      {:ok, game} = Game.start(game, "ana", @now, 1)

      assert %{alive_count: 2, winner_name: nil} = Lobby.summary(game)

      # Ana can reach Bruno, who has 1 HP left: one shot ends the game.
      tanks =
        game.tanks
        |> Map.update!("ana", &%{&1 | ap: 1, range: 99})
        |> Map.update!("bruno", &%{&1 | hp: 1})

      {:ok, game} = Game.act(%{game | tanks: tanks}, "ana", {:shoot, "bruno"}, @now)

      assert %{status: :finished, alive_count: 1, winner_name: "Ana"} = Lobby.summary(game)
    end
  end

  describe "expires_at/1" do
    test "a finished table goes 7 days after the end, a waiting one 7 days after creation" do
      assert Lobby.expires_at(%{status: :finished, finished_at: @now}) ==
               ~U[2026-03-08 12:00:00Z]

      assert Lobby.expires_at(%{status: :lobby, created_at: @now}) == ~U[2026-03-08 12:00:00Z]
    end

    test "a running table has no date: it goes when it's abandoned" do
      assert Lobby.expires_at(%{status: :running, created_at: @now}) == nil
    end
  end

  describe "expired?/2" do
    test "a finished table is kept for 7 days" do
      refute Lobby.expired?(%{status: :finished, finished_at: days_ago(6)}, @now)
      assert Lobby.expired?(%{status: :finished, finished_at: days_ago(7)}, @now)
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
