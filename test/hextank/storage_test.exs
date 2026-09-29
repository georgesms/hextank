defmodule Hextank.StorageTest do
  use ExUnit.Case, async: true

  alias Hextank.{Game, Hex, Storage}

  doctest Hextank.Storage

  defp game do
    Game.new(
      id: Storage.new_id(),
      name: "Saved table",
      visibility: :public,
      creator_id: "ana",
      tick_interval: 60,
      created_at: ~U[2026-01-01 12:00:00Z]
    )
  end

  test "a saved game loads back unchanged" do
    game = game()
    :ok = Storage.save_game(game)

    assert Storage.load_game(game.id) == {:ok, game}
  end

  test "saving again replaces the previous save and leaves no temporary file" do
    game = game()
    :ok = Storage.save_game(game)
    :ok = Storage.save_game(%{game | name: "Renamed"})

    assert {:ok, %Game{name: "Renamed"}} = Storage.load_game(game.id)
    assert game.id in Storage.list_table_ids()
  end

  test "a game saved before table settings existed loads with the default settings" do
    game = game()

    # What version 1 wrote: the game without its :settings and :action_counts.
    old_game = Map.drop(game, [:settings, :action_counts])
    path = Path.join([Application.fetch_env!(:hextank, :data_dir), "tables", game.id, "game.bin"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary({1, old_game}))

    assert Storage.load_game(game.id) == {:ok, game}
  end

  test "a game saved before action counts existed loads with none counted" do
    game = game()

    # What version 2 wrote: the game without its :action_counts field.
    old_game = Map.delete(game, :action_counts)
    path = Path.join([Application.fetch_env!(:hextank, :data_dir), "tables", game.id, "game.bin"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary({2, old_game}))

    assert {:ok, %{action_counts: %{}} = loaded} = Storage.load_game(game.id)
    assert loaded == game
  end

  test "a game saved before the maximum range existed loads with a maximum of 5" do
    game = game()

    # What version 3 wrote: settings without :max_range.
    old_game = update_in(game.settings, &Map.delete(&1, :max_range))
    path = Path.join([Application.fetch_env!(:hextank, :data_dir), "tables", game.id, "game.bin"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary({3, old_game}))

    assert {:ok, %{settings: %{max_range: 5}} = loaded} = Storage.load_game(game.id)
    assert loaded == game
  end

  test "tanks saved before hulls and turrets could turn point the default way" do
    tank = %Hextank.Tank{player_id: "ana", name: "Ana", seat: 1, position: Hex.new(0, 0, 0)}
    game = %{game() | tanks: %{"ana" => tank}}

    # What version 4 wrote: tanks without :heading and :aim.
    old_game = %{game | tanks: %{"ana" => Map.drop(tank, [:heading, :aim])}}
    path = Path.join([Application.fetch_env!(:hextank, :data_dir), "tables", game.id, "game.bin"])
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary({4, old_game}))

    assert {:ok, loaded} = Storage.load_game(game.id)
    assert %Hextank.Tank{heading: 0, aim: nil} = loaded.tanks["ana"]
    assert loaded == game
  end

  test "an unknown table is not found" do
    assert Storage.load_game(Storage.new_id()) == {:error, :not_found}
  end

  test "an id that could escape the data folder is never used" do
    assert Storage.load_game("../../../etc/passwd") == {:error, :not_found}
    assert Storage.delete_table("..") == :ok
  end

  test "a deleted table is gone" do
    game = game()
    :ok = Storage.save_game(game)
    :ok = Storage.delete_table(game.id)

    assert Storage.load_game(game.id) == {:error, :not_found}
    refute game.id in Storage.list_table_ids()
  end

  test "new ids are valid and different" do
    ids = for _ <- 1..100, do: Storage.new_id()

    assert Enum.all?(ids, &Storage.valid_id?/1)
    assert length(Enum.uniq(ids)) == 100
  end
end
