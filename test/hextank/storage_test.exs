defmodule Hextank.StorageTest do
  use ExUnit.Case, async: true

  alias Hextank.{Game, Storage}

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
