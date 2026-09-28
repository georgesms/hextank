defmodule Hextank.PlayersTest do
  use ExUnit.Case, async: true

  alias Hextank.{Player, Players}

  doctest Hextank.Player

  describe "create/2" do
    test "saves a player with a trimmed nickname" do
      {:ok, player} = Players.create("  Ana  ")

      assert player.nickname == "Ana"
      assert Players.get(player.id) == {:ok, player}
    end

    test "rejects nicknames that are too short, too long or have odd characters" do
      for nickname <- ["A", String.duplicate("a", 21), "Ana<b>", "Ana/..", 42] do
        assert Players.create(nickname) == {:error, :invalid_nickname}
      end
    end

    test "accepts accents, digits, spaces, dashes and underscores" do
      assert {:ok, %Player{nickname: "João_2 da-Silva"}} = Players.create("João_2 da-Silva")
    end
  end

  test "rename/2 saves the new nickname" do
    {:ok, player} = Players.create("Ana")
    {:ok, player} = Players.rename(player, "Ana Júlia")

    assert {:ok, %Player{nickname: "Ana Júlia"}} = Players.get(player.id)
  end

  test "reset_rejoin_link/1 bumps the token version" do
    {:ok, player} = Players.create("Ana")
    {:ok, player} = Players.reset_rejoin_link(player)

    assert {:ok, %Player{token_version: 2}} = Players.get(player.id)
  end

  test "get/1 doesn't find unknown or malformed ids" do
    assert Players.get("nobody-here-123") == {:error, :not_found}
    assert Players.get("../../etc/passwd") == {:error, :not_found}
    assert Players.get(nil) == {:error, :not_found}
  end
end
