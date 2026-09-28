defmodule Hextank.GameTest do
  use ExUnit.Case, async: true

  alias Hextank.{Board, Game, Hex, Tank}

  @now ~U[2026-01-01 12:00:00Z]
  @day 86_400

  # A game in the lobby, created by "ana".
  defp lobby_game(player_ids \\ ["ana"]) do
    game =
      Game.new(
        id: "table01",
        name: "Test table",
        visibility: :public,
        creator_id: "ana",
        tick_interval: @day,
        created_at: @now
      )

    Enum.reduce(player_ids, game, fn player_id, game ->
      {:ok, game} = Game.add_player(game, player_id, String.capitalize(player_id), @now)
      game
    end)
  end

  # A running game on a radius-3 board with an obstacle at (0, -1, 1), and tanks at
  # known positions. Each tank is {player_id, hex, fields to override}.
  defp running_game(tanks) do
    tanks =
      tanks
      |> Enum.with_index(1)
      |> Map.new(fn {{player_id, position, fields}, seat} ->
        tank = %Tank{player_id: player_id, name: player_id, seat: seat, position: position}
        {player_id, struct!(tank, fields)}
      end)

    %{
      lobby_game()
      | status: :running,
        board: Board.new(3, [Hex.new(0, -1, 1)]),
        tanks: tanks,
        started_at: @now
    }
  end

  # Ana at the centre with 3 AP, Bruno two steps away, Carla far away.
  defp standard_game do
    running_game([
      {"ana", Hex.new(0, 0, 0), ap: 3},
      {"bruno", Hex.new(2, -1, -1), []},
      {"carla", Hex.new(-3, 3, 0), []}
    ])
  end

  # Ana and Bruno alive, plus a ghost.
  defp game_with_ghost(ghost_fields) do
    running_game([
      {"ana", Hex.new(0, 0, 0), []},
      {"bruno", Hex.new(3, -3, 0), []},
      {"ghost", nil, [hp: 0] ++ ghost_fields}
    ])
  end

  defp later(seconds), do: DateTime.add(@now, seconds, :second)

  describe "add_player/4" do
    test "gives each player the next seat" do
      game = lobby_game(["ana", "bruno"])

      assert Game.tank(game, "ana").seat == 1
      assert Game.tank(game, "bruno").seat == 2
    end

    test "rejects a player who already joined" do
      assert Game.add_player(lobby_game(), "ana", "Ana", @now) == {:error, :already_joined}
    end

    test "rejects a 21st player" do
      game = lobby_game(for n <- 1..20, do: "player#{n}")
      assert Game.add_player(game, "late", "Late", @now) == {:error, :table_full}
    end

    test "rejects players once the game started" do
      assert Game.add_player(standard_game(), "dora", "Dora", @now) ==
               {:error, :game_already_started}
    end
  end

  describe "remove_player/3" do
    test "removes the player" do
      {:ok, game} = Game.remove_player(lobby_game(["ana", "bruno"]), "bruno", @now)
      assert Game.tank(game, "bruno") == nil
    end

    test "passes the creator role to the player who joined first" do
      {:ok, game} = Game.remove_player(lobby_game(["ana", "bruno", "carla"]), "ana", @now)
      assert game.creator_id == "bruno"
    end

    test "rejects a player who isn't in the game" do
      assert Game.remove_player(lobby_game(), "zeca", @now) == {:error, :not_in_game}
    end

    test "rejects leaving once the game started" do
      assert Game.remove_player(standard_game(), "bruno", @now) ==
               {:error, :game_already_started}
    end
  end

  describe "start/4" do
    test "places every tank on its own open cell, spread apart" do
      {:ok, game} = Game.start(lobby_game(["ana", "bruno", "carla"]), "ana", @now, 42)

      positions = Enum.map(Map.values(game.tanks), & &1.position)

      assert game.status == :running
      assert length(Enum.uniq(positions)) == 3
      assert Enum.all?(positions, &(&1 in Board.open_cells(game.board)))

      for a <- positions, b <- positions, a != b do
        assert Hex.distance(a, b) >= 3
      end
    end

    test "is the same for the same seed" do
      game = lobby_game(["ana", "bruno"])
      assert Game.start(game, "ana", @now, 7) == Game.start(game, "ana", @now, 7)
    end

    test "counts ticks from the start, to the second" do
      {:ok, game} =
        Game.start(lobby_game(["ana", "bruno"]), "ana", ~U[2026-01-01 12:00:00.123456Z], 1)

      assert game.started_at == ~U[2026-01-01 12:00:00Z]
      assert Game.next_tick_at(game) == ~U[2026-01-02 12:00:00Z]
    end

    test "only the creator can start" do
      assert Game.start(lobby_game(["ana", "bruno"]), "bruno", @now, 1) == {:error, :not_creator}
    end

    test "needs at least two players" do
      assert Game.start(lobby_game(), "ana", @now, 1) == {:error, :not_enough_players}
    end

    test "can't start twice" do
      assert Game.start(standard_game(), "ana", @now, 1) == {:error, :game_already_started}
    end
  end

  describe "table settings" do
    defp lobby_with_settings(settings, player_ids) do
      game = %{lobby_game() | settings: Map.merge(Hextank.Settings.defaults(), settings)}

      Enum.reduce(tl(player_ids), game, fn player_id, game ->
        {:ok, game} = Game.add_player(game, player_id, player_id, @now)
        game
      end)
    end

    test "tanks start with the chosen HP and range" do
      game = lobby_with_settings(%{start_hp: 5, start_range: 1}, ["ana", "bruno"])

      assert %Tank{hp: 5, range: 1} = Game.tank(game, "bruno")
    end

    test "a fixed board radius and obstacle share are used at the start" do
      game = lobby_with_settings(%{board_radius: 7, obstacle_percent: 0}, ["ana", "bruno"])
      {:ok, game} = Game.start(game, "ana", @now, 1)

      assert game.board.radius == 7
      assert MapSet.size(game.board.obstacles) == 0
    end

    test "tanks start further apart when their range is bigger" do
      game = lobby_with_settings(%{start_range: 4, board_radius: 12}, ["ana", "bruno", "carla"])
      {:ok, game} = Game.start(game, "ana", @now, 3)
      positions = Enum.map(Map.values(game.tanks), & &1.position)

      for a <- positions, b <- positions, a != b do
        assert Hex.distance(a, b) >= 5
      end
    end

    test "a board without an open cell for everyone can't start" do
      players = for n <- 1..7, do: "p#{n}"
      game = lobby_with_settings(%{board_radius: 1, obstacle_percent: 20}, ["ana" | players])

      assert Game.start(game, "ana", @now, 1) == {:error, :board_too_small}
    end
  end

  describe "freeze/3" do
    test "removes a banned player from a game that hasn't started" do
      {:ok, game} = Game.freeze(lobby_game(["ana", "bruno"]), "bruno", @now)
      assert Game.tank(game, "bruno") == nil
    end

    test "freezes the tank of a running game: it stays on the board and can't act" do
      {:ok, game} = Game.freeze(standard_game(), "ana", @now)

      assert %Tank{frozen: true, position: %Hex{}} = Game.tank(game, "ana")
      assert Game.act(game, "ana", :upgrade_range, @now) == {:error, :frozen}
    end

    test "a frozen tank can still be shot" do
      game = running_game([{"ana", Hex.new(0, 0, 0), []}, {"bruno", Hex.new(1, 0, -1), ap: 1}])
      {:ok, game} = Game.freeze(game, "ana", @now)

      {:ok, game} = Game.act(game, "bruno", {:shoot, "ana"}, @now)
      assert Game.tank(game, "ana").hp == 2
    end

    test "leaves finished games alone" do
      game = %{standard_game() | status: :finished}
      assert Game.freeze(game, "ana", @now) == {:ok, game}
    end
  end

  describe "catch_up/2" do
    test "does nothing before the first tick is due" do
      game = standard_game()
      assert Game.catch_up(game, later(@day - 1)) == game
    end

    test "gives 1 AP to every living tank when one tick is due" do
      game = Game.catch_up(standard_game(), later(@day))

      assert game.ticks == 1
      assert Game.tank(game, "ana").ap == 4
      assert Game.tank(game, "bruno").ap == 1
    end

    test "applies every missed tick at once" do
      game = Game.catch_up(standard_game(), later(5 * @day + 10))

      assert game.ticks == 5
      assert Game.tank(game, "bruno").ap == 5
    end

    test "never applies the same tick twice" do
      game = standard_game() |> Game.catch_up(later(@day)) |> Game.catch_up(later(@day + 60))
      assert game.ticks == 1
    end

    test "gives ghosts one vote, however many ticks were missed" do
      game =
        running_game([
          {"ana", Hex.new(0, 0, 0), []},
          {"bruno", Hex.new(1, 0, -1), []},
          {"ghost", nil, hp: 0}
        ])
        |> Game.catch_up(later(3 * @day))

      ghost = Game.tank(game, "ghost")
      assert ghost.has_vote
      assert ghost.ap == 0
    end

    test "does nothing when the game isn't running" do
      game = lobby_game()
      assert Game.catch_up(game, later(10 * @day)) == game
    end
  end

  describe "act/4 with {:move, hex}" do
    test "drives along the shortest path for 1 AP per cell" do
      {:ok, game} = Game.act(standard_game(), "ana", {:move, Hex.new(2, 0, -2)}, @now)

      tank = Game.tank(game, "ana")
      assert tank.position == Hex.new(2, 0, -2)
      assert tank.ap == 1
      assert [%{type: :moved, actor: "ana", steps: 2} | _] = game.events
    end

    test "drives around rocks, paying for the detour" do
      # Straight ahead, (0, -1, 1) is a rock: 3 cells instead of 2.
      {:ok, game} = Game.act(standard_game(), "ana", {:move, Hex.new(0, -2, 2)}, @now)
      assert Game.tank(game, "ana").ap == 0
    end

    test "needs 1 AP per cell of the path" do
      game = running_game([{"ana", Hex.new(0, 0, 0), ap: 1}, {"bruno", Hex.new(3, -3, 0), []}])

      assert Game.act(game, "ana", {:move, Hex.new(2, 0, -2)}, @now) == {:error, :not_enough_ap}
    end

    test "rejects a cell that can't be reached" do
      game = running_game([{"ana", Hex.new(0, 0, 0), ap: 9}, {"bruno", Hex.new(-3, 3, 0), []}])
      walled_in = [Hex.new(2, -3, 1), Hex.new(2, -2, 0), Hex.new(3, -2, -1)]
      game = %{game | board: Board.new(3, walled_in)}

      assert Game.act(game, "ana", {:move, Hex.new(3, -3, 0)}, @now) == {:error, :unreachable}
    end

    test "rejects an obstacle" do
      assert Game.act(standard_game(), "ana", {:move, Hex.new(0, -1, 1)}, @now) ==
               {:error, :obstacle}
    end

    test "rejects a cell off the board" do
      game = running_game([{"ana", Hex.new(3, 0, -3), ap: 1}, {"bruno", Hex.new(0, 0, 0), []}])

      assert Game.act(game, "ana", {:move, Hex.new(4, 0, -4)}, @now) == {:error, :off_board}
    end

    test "rejects a cell with a tank on it" do
      game = running_game([{"ana", Hex.new(0, 0, 0), ap: 1}, {"bruno", Hex.new(1, 0, -1), []}])

      assert Game.act(game, "ana", {:move, Hex.new(1, 0, -1)}, @now) == {:error, :cell_occupied}
    end

    test "needs 1 AP even for a neighbouring cell" do
      assert Game.act(standard_game(), "bruno", {:move, Hex.new(2, 0, -2)}, @now) ==
               {:error, :not_enough_ap}
    end
  end

  describe "act/4 with {:shoot, target_id}" do
    test "deals 1 damage to a tank within range for 1 AP" do
      {:ok, game} = Game.act(standard_game(), "ana", {:shoot, "bruno"}, @now)

      assert Game.tank(game, "bruno").hp == 2
      assert Game.tank(game, "ana").ap == 2
      assert [%{type: :shot, actor: "ana", target: "bruno"} | _] = game.events
    end

    test "destroys a tank with 1 HP: it becomes a ghost and leaves the board" do
      game =
        running_game([
          {"ana", Hex.new(0, 0, 0), ap: 1},
          {"bruno", Hex.new(1, 0, -1), hp: 1},
          {"carla", Hex.new(-3, 3, 0), []}
        ])

      {:ok, game} = Game.act(game, "ana", {:shoot, "bruno"}, @now)

      bruno = Game.tank(game, "bruno")
      assert Tank.ghost?(bruno)
      assert bruno.position == nil
      assert game.status == :running
      assert [%{type: :destroyed, target: "bruno"} | _] = game.events
    end

    test "destroying the second-to-last tank wins the game" do
      game = running_game([{"ana", Hex.new(0, 0, 0), ap: 1}, {"bruno", Hex.new(1, 0, -1), hp: 1}])

      {:ok, game} = Game.act(game, "ana", {:shoot, "bruno"}, later(60))

      assert game.status == :finished
      assert game.winner_id == "ana"
      assert game.finished_at == later(60)
      assert [%{type: :won, actor: "ana"} | _] = game.events
    end

    test "rejects a tank out of range" do
      assert Game.act(standard_game(), "ana", {:shoot, "carla"}, @now) == {:error, :out_of_range}
    end

    test "rejects shooting yourself" do
      assert Game.act(standard_game(), "ana", {:shoot, "ana"}, @now) ==
               {:error, :cannot_target_self}
    end

    test "rejects ghosts and unknown players as targets" do
      game =
        running_game([
          {"ana", Hex.new(0, 0, 0), ap: 1},
          {"bruno", Hex.new(1, 0, -1), []},
          {"ghost", nil, hp: 0}
        ])

      assert Game.act(game, "ana", {:shoot, "ghost"}, @now) == {:error, :invalid_target}
      assert Game.act(game, "ana", {:shoot, "nobody"}, @now) == {:error, :invalid_target}
    end

    test "needs 1 AP" do
      assert Game.act(standard_game(), "bruno", {:shoot, "ana"}, @now) == {:error, :not_enough_ap}
    end
  end

  describe "act/4 with :upgrade_range" do
    test "adds 1 to the range for 1 AP" do
      {:ok, game} = Game.act(standard_game(), "ana", :upgrade_range, @now)

      assert Game.tank(game, "ana").range == 3
      assert Game.tank(game, "ana").ap == 2
    end

    test "needs 1 AP" do
      assert Game.act(standard_game(), "bruno", :upgrade_range, @now) == {:error, :not_enough_ap}
    end
  end

  describe "act/4 with {:give_ap, target_id}" do
    test "moves 1 AP to a tank within range" do
      {:ok, game} = Game.act(standard_game(), "ana", {:give_ap, "bruno"}, @now)

      assert Game.tank(game, "ana").ap == 2
      assert Game.tank(game, "bruno").ap == 1
    end

    test "rejects a tank out of range" do
      assert Game.act(standard_game(), "ana", {:give_ap, "carla"}, @now) ==
               {:error, :out_of_range}
    end

    test "rejects giving to yourself" do
      assert Game.act(standard_game(), "ana", {:give_ap, "ana"}, @now) ==
               {:error, :cannot_target_self}
    end
  end

  describe "act/4 with {:vote, target_id}" do
    test "gives 1 AP to any living tank, however far, and uses up the vote" do
      {:ok, game} = Game.act(game_with_ghost(has_vote: true), "ghost", {:vote, "bruno"}, @now)

      assert Game.tank(game, "bruno").ap == 1
      refute Game.tank(game, "ghost").has_vote
    end

    test "needs a vote left" do
      assert Game.act(game_with_ghost(has_vote: false), "ghost", {:vote, "ana"}, @now) ==
               {:error, :no_vote_left}
    end

    test "living tanks can't vote" do
      assert Game.act(game_with_ghost([]), "ana", {:vote, "bruno"}, @now) ==
               {:error, :not_a_ghost}
    end

    test "ghosts can't use tank actions" do
      assert Game.act(game_with_ghost(ap: 5), "ghost", :upgrade_range, @now) ==
               {:error, :tank_destroyed}
    end
  end

  describe "act/4 in general" do
    test "rejects players who aren't in the game" do
      assert Game.act(standard_game(), "zeca", :upgrade_range, @now) == {:error, :not_in_game}
    end

    test "rejects frozen tanks" do
      game =
        running_game([
          {"ana", Hex.new(0, 0, 0), ap: 1, frozen: true},
          {"bruno", Hex.new(3, -3, 0), []}
        ])

      assert Game.act(game, "ana", :upgrade_range, @now) == {:error, :frozen}
    end

    test "only works while the game is running" do
      assert Game.act(lobby_game(), "ana", :upgrade_range, @now) == {:error, :game_not_running}
    end

    test "rejects unknown actions" do
      assert Game.act(standard_game(), "ana", :fly, @now) == {:error, :unknown_action}
    end

    test "keeps only the last 50 events" do
      game = running_game([{"ana", Hex.new(0, 0, 0), ap: 60}, {"bruno", Hex.new(3, -3, 0), []}])

      game =
        Enum.reduce(1..60, game, fn _, game ->
          {:ok, game} = Game.act(game, "ana", :upgrade_range, @now)
          game
        end)

      assert length(game.events) == 50
    end

    test "counts each kind of action that succeeded" do
      game = standard_game()
      {:ok, game} = Game.act(game, "ana", :upgrade_range, @now)
      {:ok, game} = Game.act(game, "ana", {:give_ap, "bruno"}, @now)
      {:ok, game} = Game.act(game, "ana", :upgrade_range, @now)
      {:error, :not_enough_ap} = Game.act(game, "ana", :upgrade_range, @now)

      assert game.action_counts == %{upgrade_range: 2, give_ap: 1}
    end
  end

  describe "path/3, check_target/3 and tanks_in_range/2" do
    test "path/3 gives the cells to cross, whatever the AP" do
      assert {:ok, path} = Game.path(standard_game(), "bruno", Hex.new(0, -2, 2))
      assert List.last(path) == Hex.new(0, -2, 2)
      refute Hex.new(0, -1, 1) in path
    end

    test "path/3 explains why a cell can't be a destination" do
      assert Game.path(standard_game(), "ana", Hex.new(0, -1, 1)) == {:error, :obstacle}
      assert Game.path(standard_game(), "ana", Hex.new(2, -1, -1)) == {:error, :cell_occupied}
    end

    test "check_target/3 says whether a tank is within range" do
      assert Game.check_target(standard_game(), "ana", "bruno") == :ok
      assert Game.check_target(standard_game(), "ana", "carla") == {:error, :out_of_range}
      assert Game.check_target(standard_game(), "ana", "ana") == {:error, :cannot_target_self}
    end

    test "list the living tanks within range, not yourself" do
      assert Enum.map(Game.tanks_in_range(standard_game(), "ana"), & &1.player_id) == ["bruno"]
    end
  end
end
