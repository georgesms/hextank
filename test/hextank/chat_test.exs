defmodule Hextank.ChatTest do
  use ExUnit.Case, async: true

  alias Hextank.{Chat, Game, Players, Storage}

  @now ~U[2026-01-01 12:00:00Z]

  # A game in the lobby with Ana, Bruno and Carla, all saved players.
  setup do
    [ana, bruno, carla] =
      for name <- ["Ana", "Bruno", "Carla"] do
        {:ok, player} = Players.create(name)
        player
      end

    game =
      Game.new(
        id: Storage.new_id(),
        name: "Chat table",
        visibility: :public,
        creator_id: ana.id,
        tick_interval: 86_400,
        created_at: @now
      )

    game =
      Enum.reduce([ana, bruno, carla], game, fn player, game ->
        {:ok, game} = Game.add_player(game, player.id, player.nickname, @now)
        game
      end)

    %{game: game, ana: ana, bruno: bruno, carla: carla}
  end

  defp later(seconds), do: DateTime.add(@now, seconds, :second)

  describe "table chat" do
    test "is saved, broadcast and seen by everyone", %{game: game, ana: ana} do
      Phoenix.PubSub.subscribe(Hextank.PubSub, "table:#{game.id}")

      {:ok, message} = Chat.send_message(game, ana, "  Alliance, anyone? ", nil, @now)

      assert message.text == "Alliance, anyone?"
      assert message.name == "Ana"
      assert_receive {:chat_message, ^message}
      assert Chat.history(game.id, nil) == [message]
    end
  end

  describe "private messages" do
    test "reach only the sender and the recipient", ctx do
      %{game: game, ana: ana, bruno: bruno, carla: carla} = ctx
      Chat.subscribe_private(game.id, bruno.id)
      Chat.subscribe_private(game.id, carla.id)

      {:ok, message} = Chat.send_message(game, ana, "Let's get Carla", bruno.id, @now)

      # This test process listens on both Bruno's and Carla's topics: exactly one copy
      # arrives, Bruno's.
      assert_receive {:chat_message, ^message}
      refute_receive {:chat_message, _}, 50

      assert Chat.history(game.id, ana.id) == [message]
      assert Chat.history(game.id, bruno.id) == [message]
      assert Chat.history(game.id, carla.id) == []
      assert Chat.history(game.id, nil) == []
    end

    test "can't go to yourself or to someone outside the table", %{game: game, ana: ana} do
      assert Chat.send_message(game, ana, "hi", ana.id) == {:error, :invalid_recipient}
      assert Chat.send_message(game, ana, "hi", "nobody-at-all") == {:error, :invalid_recipient}
    end
  end

  describe "rules for sending" do
    test "only players of the table can write", %{game: game} do
      {:ok, outsider} = Players.create("Zeca")
      assert Chat.send_message(game, outsider, "hello") == {:error, :not_in_game}
    end

    test "banned players can't write", %{game: game, ana: ana} do
      :ok = Players.ban(ana)
      assert Chat.send_message(game, ana, "hello") == {:error, :banned}
    end

    test "messages can't be empty or longer than 500 characters", %{game: game, ana: ana} do
      assert Chat.send_message(game, ana, "   ") == {:error, :empty_message}

      assert Chat.send_message(game, ana, String.duplicate("a", 501)) ==
               {:error, :message_too_long}
    end

    test "a prohibited word stops the message and gives a strike", %{game: game, ana: ana} do
      assert Chat.send_message(game, ana, "you badword") == {:error, {:prohibited, :warning}}
      assert Chat.history(game.id, ana.id) == []
    end
  end

  describe "unread_count/2" do
    test "counts messages from others since the last read", ctx do
      %{game: game, ana: ana, bruno: bruno} = ctx
      {:ok, _} = Chat.send_message(game, bruno, "one", nil, later(10))
      {:ok, _} = Chat.send_message(game, ana, "mine", nil, later(20))
      assert Chat.unread_count(game.id, ana.id) == 1

      :ok = Chat.mark_read(game.id, ana.id, later(30))
      assert Chat.unread_count(game.id, ana.id) == 0

      {:ok, _} = Chat.send_message(game, bruno, "two", ana.id, later(40))
      assert Chat.unread_count(game.id, ana.id) == 1
    end
  end

  test "too_fast?/2 allows 5 messages in 10 seconds" do
    four = for s <- 1..4, do: later(s)
    five = [later(5) | four]

    refute Chat.too_fast?(four, later(6))
    assert Chat.too_fast?(five, later(6))
    refute Chat.too_fast?(five, later(20))
  end
end
