defmodule Hextank.TablesTest do
  # Not async: these tests share the table registry, the lobby and the idle timeout.
  use ExUnit.Case, async: false

  alias Hextank.{Game, Player, Storage, Tables}

  @ana %Player{id: "ana", nickname: "Ana", created_at: ~U[2026-01-01 00:00:00Z]}

  @attrs %{name: "Test table", visibility: :public, tick_interval: 86_400}

  defp create_table(attrs \\ %{}) do
    {:ok, game} = Tables.create_table(@ana, Map.merge(@attrs, attrs))
    game
  end

  defp running_table(attrs \\ %{}) do
    game = create_table(attrs)
    {:ok, _} = Tables.join(game.id, "bruno", "Bruno")
    {:ok, game} = Tables.start(game.id, "ana")
    game
  end

  defp table_pid(id) do
    [{pid, _}] = Registry.lookup(Hextank.Tables.Registry, id)
    pid
  end

  describe "create_table/4" do
    test "saves a table with the creator as first player" do
      game = create_table()

      assert {:ok, saved} = Storage.load_game(game.id)
      assert saved.creator_id == "ana"
      assert Map.keys(saved.tanks) == ["ana"]
    end

    test "lists public tables in the lobby, and every table for its players" do
      public = create_table()
      private = create_table(%{visibility: :private})

      public_ids = Enum.map(Tables.list_public(), & &1.id)
      assert public.id in public_ids
      refute private.id in public_ids

      ana_ids = Enum.map(Tables.list_for_player("ana"), & &1.id)
      assert public.id in ana_ids
      assert private.id in ana_ids
    end

    test "keeps the chosen settings" do
      game = create_table(%{settings: %{start_hp: 5}})

      assert game.settings.start_hp == 5
      assert {:ok, %Game{settings: %{start_hp: 5}}} = Storage.load_game(game.id)
    end

    test "rejects bad names, visibilities, tick intervals and settings" do
      assert Tables.create_table(@ana, %{@attrs | name: " x "}) ==
               {:error, :invalid_name}

      assert Tables.create_table(@ana, %{@attrs | visibility: :secret}) ==
               {:error, :invalid_visibility}

      assert Tables.create_table(@ana, %{@attrs | tick_interval: 5}) ==
               {:error, :invalid_tick_interval}

      assert Tables.create_table(@ana, Map.put(@attrs, :settings, %{start_hp: 0})) ==
               {:error, :invalid_settings}
    end
  end

  describe "changing a table" do
    test "joins, starts and acts, telling every watcher" do
      game = create_table()
      {:ok, _} = Tables.watch(game.id)

      {:ok, _} = Tables.join(game.id, "bruno", "Bruno")
      assert_receive {:game_updated, %Game{status: :lobby}}

      {:ok, _} = Tables.start(game.id, "ana")
      assert_receive {:game_updated, %Game{status: :running}}

      assert Tables.act(game.id, "ana", :upgrade_range) == {:error, :not_enough_ap}
    end

    test "every change is saved to disk" do
      game = create_table()
      {:ok, _} = Tables.join(game.id, "bruno", "Bruno")

      {:ok, saved} = Storage.load_game(game.id)
      assert Map.has_key?(saved.tanks, "bruno")
    end

    test "unknown and malformed ids are not found" do
      assert Tables.get(Storage.new_id()) == {:error, :not_found}
      assert Tables.watch("../secret") == {:error, :not_found}
    end
  end

  describe "bans" do
    test "a banned player can't create or join tables, and their place is frozen" do
      {:ok, bruno} = Hextank.Players.create("Bruno")

      # Bruno waits in one table's lobby and plays in another.
      lobby = create_table()
      {:ok, _} = Tables.join(lobby.id, bruno.id, "Bruno")
      game = create_table()
      {:ok, _} = Tables.join(game.id, bruno.id, "Bruno")
      {:ok, _} = Tables.start(game.id, "ana")

      :ok = Hextank.Players.ban(bruno)

      assert Tables.join(create_table().id, bruno.id, "Bruno") == {:error, :banned}
      assert Tables.create_table(bruno, @attrs) == {:error, :banned}

      {:ok, lobby} = Tables.get(lobby.id)
      refute Map.has_key?(lobby.tanks, bruno.id)

      {:ok, game} = Tables.get(game.id)
      assert Game.tank(game, bruno.id).frozen
    end
  end

  describe "ticks" do
    test "a table that wakes up applies the ticks it missed while asleep" do
      game = running_table()

      # Pretend the game started 3 days ago, while the table was asleep.
      pid = table_pid(game.id)
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

      three_days_ago = DateTime.add(game.started_at, -3 * 86_400, :second)
      :ok = Storage.save_game(%{game | started_at: three_days_ago})

      {:ok, game} = Tables.get(game.id)
      assert game.ticks == 3
      assert Game.tank(game, "ana").ap == 3

      # And the catch-up was saved.
      assert {:ok, %Game{ticks: 3}} = Storage.load_game(game.id)
    end

    test "a watched table ticks on time" do
      game = running_table(%{tick_interval: 60})
      {:ok, _} = Tables.watch(game.id)

      # A tick message before the tick is due changes nothing.
      pid = table_pid(game.id)
      send(pid, :tick)
      _ = :sys.get_state(pid)
      refute_received {:game_updated, %Game{ticks: 1}}

      # Move the start back one minute, so the first tick is due right now.
      :sys.replace_state(pid, fn state ->
        %{state | game: %{state.game | started_at: DateTime.add(state.game.started_at, -60)}}
      end)

      send(pid, :tick)
      assert_receive {:game_updated, %Game{ticks: 1}}
    end
  end

  describe "delete/1" do
    test "removes the files, the lobby entry and the process, and tells the watchers" do
      game = running_table()
      {:ok, _game} = Tables.watch(game.id)
      pid = table_pid(game.id)
      ref = Process.monitor(pid)

      assert Tables.delete(game.id) == :ok

      assert_receive :table_deleted
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      assert Storage.load_game(game.id) == {:error, :not_found}
      refute Enum.any?(Tables.list_for_player("ana"), &(&1.id == game.id))
      assert Tables.get(game.id) == {:error, :not_found}
    end

    test "wakes a sleeping table to delete it, and an unknown one is not found" do
      game = create_table()

      assert Tables.delete(game.id) == :ok
      assert Storage.load_game(game.id) == {:error, :not_found}
      assert Tables.delete(game.id) == {:error, :not_found}
    end
  end

  describe "sleeping" do
    test "a new table only starts a process when it's used" do
      game = create_table()
      assert Registry.lookup(Hextank.Tables.Registry, game.id) == []

      {:ok, _} = Tables.get(game.id)
      assert [{_pid, _}] = Registry.lookup(Hextank.Tables.Registry, game.id)
    end

    test "a table nobody watches stops after the idle timeout, and wakes up on demand" do
      game = create_table()
      {:ok, _} = Tables.get(game.id)
      pid = table_pid(game.id)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000

      # Straight away, even while the Registry may still list the stopped process.
      assert {:ok, %Game{id: id}} = Tables.get(game.id)
      assert id == game.id
      assert table_pid(game.id) != pid
    end

    test "a watched table stays awake until its watcher is gone" do
      game = create_table()
      test_process = self()

      watcher =
        spawn(fn ->
          {:ok, _} = Tables.watch(game.id)
          send(test_process, :watching)
          receive do: (:stop -> :ok)
        end)

      assert_receive :watching
      pid = table_pid(game.id)
      ref = Process.monitor(pid)

      # Well past the 200 ms idle timeout, the table is still there.
      refute_receive {:DOWN, ^ref, :process, ^pid, _}, 500

      send(watcher, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end
  end
end
