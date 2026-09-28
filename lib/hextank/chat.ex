defmodule Hextank.Chat do
  @moduledoc """
  Table chat and private messages (see README, *Chat*). Diplomacy is half the game.

  Chat is not game state: messages are appended to the table's `chat.jsonl` and
  broadcast on PubSub, without going through the table process.

    * Table chat goes to `"table:<id>"`, the topic every table page already watches.
    * A private message goes to `"table:<id>:player:<player_id>"` of its sender and
      its recipient only, and the history is filtered on the server, so nobody else
      ever receives it.

  A message is a map: `%{id, at, from, name, to, text}`, where `to` is `nil` for the
  table chat.
  """

  alias Hextank.{Game, Player, Players, Storage}
  alias Hextank.Players.Bans

  @max_length 500
  @history 100

  # At most this many messages in this many seconds per player.
  @rate_limit_count 5
  @rate_limit_seconds 10

  @type message :: %{
          id: String.t(),
          at: DateTime.t(),
          from: String.t(),
          name: String.t(),
          to: String.t() | nil,
          text: String.t()
        }

  @doc """
  Sends a message to the whole table (`to: nil`) or to one player. Only players of
  the table can write. The text is screened by moderation first
  (`Hextank.Players.screen/3`): a prohibited word means the message is neither saved
  nor sent.
  """
  @spec send_message(Game.t(), Player.t(), String.t(), String.t() | nil, DateTime.t()) ::
          {:ok, message()} | {:error, term()}
  def send_message(game, %Player{} = player, text, to \\ nil, now \\ DateTime.utc_now()) do
    with :ok <- check_member(game, player.id),
         :ok <- check_not_banned(player.id),
         {:ok, text} <- check_text(text),
         :ok <- check_recipient(game, player.id, to),
         :ok <- Players.screen(player, text, game.id) do
      message = %{
        id: Storage.new_id(),
        at: now,
        from: player.id,
        name: Game.tank(game, player.id).name,
        to: to,
        text: text
      }

      :ok = Storage.append_chat(game.id, to_json(message))
      broadcast(game.id, message)
      {:ok, message}
    end
  end

  defp check_member(game, player_id) do
    if Game.tank(game, player_id), do: :ok, else: {:error, :not_in_game}
  end

  defp check_not_banned(player_id) do
    if Bans.banned?(player_id), do: {:error, :banned}, else: :ok
  end

  defp check_text(text) when is_binary(text) do
    text = String.trim(text)

    cond do
      text == "" -> {:error, :empty_message}
      String.length(text) > @max_length -> {:error, :message_too_long}
      true -> {:ok, text}
    end
  end

  defp check_text(_text), do: {:error, :empty_message}

  defp check_recipient(_game, _from, nil), do: :ok
  defp check_recipient(_game, from, from), do: {:error, :invalid_recipient}

  defp check_recipient(game, _from, to) do
    if Game.tank(game, to), do: :ok, else: {:error, :invalid_recipient}
  end

  defp broadcast(table_id, %{to: nil} = message) do
    Phoenix.PubSub.broadcast(Hextank.PubSub, "table:#{table_id}", {:chat_message, message})
  end

  defp broadcast(table_id, message) do
    for player_id <- [message.from, message.to] do
      Phoenix.PubSub.broadcast(
        Hextank.PubSub,
        private_topic(table_id, player_id),
        {:chat_message, message}
      )
    end
  end

  @doc """
  Subscribes the caller to the player's private messages at this table. Table chat
  arrives through `Hextank.Tables.watch/1`.
  """
  @spec subscribe_private(String.t(), String.t()) :: :ok
  def subscribe_private(table_id, player_id) do
    Phoenix.PubSub.subscribe(Hextank.PubSub, private_topic(table_id, player_id))
  end

  defp private_topic(table_id, player_id), do: "table:#{table_id}:player:#{player_id}"

  @doc """
  The last messages the viewer may see, oldest first: the table chat plus their own
  private messages. A viewer who isn't playing (`nil`) sees the table chat only.
  """
  @spec history(String.t(), String.t() | nil) :: [message()]
  def history(table_id, viewer_id) do
    table_id
    |> Storage.read_chat(@history)
    |> Enum.map(&from_json/1)
    |> Enum.filter(&visible?(&1, viewer_id))
  end

  @doc "Whether the viewer may see a message."
  @spec visible?(message(), String.t() | nil) :: boolean()
  def visible?(%{to: nil}, _viewer_id), do: true
  def visible?(%{from: viewer_id}, viewer_id), do: true
  def visible?(%{to: viewer_id}, viewer_id), do: true
  def visible?(_message, _viewer_id), do: false

  ## Unread messages

  @doc "Remembers that the player has read the table's chat up to `now`."
  @spec mark_read(String.t(), String.t(), DateTime.t()) :: :ok
  def mark_read(table_id, player_id, now \\ DateTime.utc_now()) do
    Storage.save_last_read(table_id, player_id, now)
  end

  @doc "How many messages from others the player hasn't read yet."
  @spec unread_count(String.t(), String.t()) :: non_neg_integer()
  def unread_count(table_id, player_id) do
    last_read = Storage.load_last_read(table_id, player_id)

    table_id
    |> history(player_id)
    |> Enum.count(fn message ->
      message.from != player_id and
        (last_read == nil or DateTime.after?(message.at, last_read))
    end)
  end

  ## Rate limit

  @doc """
  Whether a player sending now would go over #{@rate_limit_count} messages in
  #{@rate_limit_seconds} seconds. `sent_at` is when they sent their recent messages;
  the table page keeps that list.
  """
  @spec too_fast?([DateTime.t()], DateTime.t()) :: boolean()
  def too_fast?(sent_at, now) do
    recent = Enum.count(sent_at, &(DateTime.diff(now, &1, :second) < @rate_limit_seconds))
    recent >= @rate_limit_count
  end

  ## JSON: one line of chat.jsonl

  defp to_json(message), do: %{message | at: DateTime.to_iso8601(message.at)}

  defp from_json(json) do
    {:ok, at, _offset} = DateTime.from_iso8601(json["at"])

    %{
      id: json["id"],
      at: at,
      from: json["from"],
      name: json["name"],
      to: json["to"],
      text: json["text"]
    }
  end
end
