defmodule Hextank.Storage do
  @moduledoc """
  All reading and writing of files (see README, *Architecture*). Nothing else in
  the app touches `File`.

  Data lives under the `:data_dir` config:

      tables/<id>/game.bin                the %Game{}, rewritten after every change
      tables/<id>/chat.jsonl              chat messages, one JSON object per line,
                                          only ever appended to
      tables/<id>/reads/<player_id>.bin   when the player last read the chat
      players/<id>.bin                    a %Player{}

  Terms are saved with `:erlang.term_to_binary/1`, wrapped as `{version, term}` so a
  future change to the shape of `%Game{}` can still read old files (see CLAUDE.md,
  *Deployment rules*).
  """

  alias Hextank.{Game, Player, Settings}

  @format_version 5

  # Ids end up in file paths, so they must never contain "/" or "..".
  @id_format ~r/\A[A-Za-z0-9_-]{8,32}\z/

  @doc "A new random id, safe to use in URLs and file names."
  @spec new_id() :: String.t()
  def new_id, do: 9 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  @doc """
  Whether a string is a valid id. Ids coming from URLs are checked before they get
  anywhere near a file path.

      iex> Storage.valid_id?("aB3_x-9Qk2Lm")
      true

      iex> Storage.valid_id?("../../etc")
      false
  """
  @spec valid_id?(term()) :: boolean()
  def valid_id?(id), do: is_binary(id) and Regex.match?(@id_format, id)

  ## Games

  @doc "Saves a game, replacing the previous save."
  @spec save_game(Game.t()) :: :ok
  def save_game(%Game{id: id} = game), do: write_term(table_file(id, "game.bin"), game)

  @doc "Loads a saved game."
  @spec load_game(String.t()) :: {:ok, Game.t()} | {:error, :not_found}
  def load_game(id) do
    if valid_id?(id), do: read_term(table_file(id, "game.bin")), else: {:error, :not_found}
  end

  @doc "The ids of every saved table."
  @spec list_table_ids() :: [String.t()]
  def list_table_ids do
    case File.ls(tables_dir()) do
      {:ok, names} -> Enum.filter(names, &valid_id?/1)
      {:error, :enoent} -> []
    end
  end

  @doc "Deletes everything saved for a table."
  @spec delete_table(String.t()) :: :ok
  def delete_table(id) do
    if valid_id?(id), do: File.rm_rf!(table_dir(id))
    :ok
  end

  ## Chat

  @doc "The size of a table's chat file in bytes (0 without one). Doesn't read it."
  @spec chat_size(String.t()) :: non_neg_integer()
  def chat_size(table_id) do
    case File.stat(table_file(table_id, "chat.jsonl")) do
      {:ok, stat} -> stat.size
      {:error, _reason} -> 0
    end
  end

  @doc """
  Adds one chat message (a map that JSON can encode) at the end of the table's chat
  file. Appending is safe with several writers: each message is one small write.
  """
  @spec append_chat(String.t(), map()) :: :ok
  def append_chat(table_id, message) do
    path = table_file(table_id, "chat.jsonl")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, JSON.encode!(message) <> "\n", [:append])
  end

  @doc "The last `limit` chat messages of a table, oldest first, as JSON maps."
  @spec read_chat(String.t(), pos_integer()) :: [map()]
  def read_chat(table_id, limit) do
    path = table_file(table_id, "chat.jsonl")

    if File.exists?(path) do
      path |> File.stream!() |> Enum.take(-limit) |> Enum.map(&JSON.decode!/1)
    else
      []
    end
  end

  @doc "Remembers when a player last read a table's chat."
  @spec save_last_read(String.t(), String.t(), DateTime.t()) :: :ok
  def save_last_read(table_id, player_id, at), do: write_term(reads_file(table_id, player_id), at)

  @doc "When a player last read a table's chat, or `nil`."
  @spec load_last_read(String.t(), String.t()) :: DateTime.t() | nil
  def load_last_read(table_id, player_id) do
    case read_term(reads_file(table_id, player_id)) do
      {:ok, at} -> at
      {:error, :not_found} -> nil
    end
  end

  ## Players

  @doc "Saves a player, replacing the previous save."
  @spec save_player(Player.t()) :: :ok
  def save_player(%Player{id: id} = player), do: write_term(player_file(id), player)

  @doc "Loads a saved player."
  @spec load_player(term()) :: {:ok, Player.t()} | {:error, :not_found}
  def load_player(id) do
    if valid_id?(id), do: read_term(player_file(id)), else: {:error, :not_found}
  end

  @doc "The ids of every saved player."
  @spec list_player_ids() :: [String.t()]
  def list_player_ids do
    case File.ls(Path.join(data_dir(), "players")) do
      {:ok, names} ->
        names
        |> Enum.filter(&String.ends_with?(&1, ".bin"))
        |> Enum.map(&Path.basename(&1, ".bin"))
        |> Enum.filter(&valid_id?/1)

      {:error, :enoent} ->
        []
    end
  end

  ## Paths

  defp data_dir, do: Application.fetch_env!(:hextank, :data_dir)
  defp tables_dir, do: Path.join(data_dir(), "tables")

  defp table_dir(id) do
    if not valid_id?(id), do: raise(ArgumentError, "invalid id: #{inspect(id)}")
    Path.join(tables_dir(), id)
  end

  defp table_file(id, name), do: Path.join(table_dir(id), name)

  defp reads_file(table_id, player_id) do
    if not valid_id?(player_id), do: raise(ArgumentError, "invalid id: #{inspect(player_id)}")
    Path.join([table_dir(table_id), "reads", player_id <> ".bin"])
  end

  defp player_file(id) do
    if not valid_id?(id), do: raise(ArgumentError, "invalid id: #{inspect(id)}")
    Path.join([data_dir(), "players", id <> ".bin"])
  end

  ## Terms on disk

  # Write to a temporary file, then rename it over the real one. A rename is atomic,
  # so a crash in the middle never leaves half a file behind.
  defp write_term(path, term) do
    File.mkdir_p!(Path.dirname(path))
    temporary = path <> ".tmp"
    File.write!(temporary, :erlang.term_to_binary({@format_version, term}))
    File.rename!(temporary, path)
  end

  defp read_term(path) do
    case File.read(path) do
      {:ok, binary} -> {:ok, decode(:erlang.binary_to_term(binary))}
      {:error, :enoent} -> {:error, :not_found}
    end
  end

  # One clause per save format. When the format changes, bump @format_version and
  # add a clause here that upgrades the old shape.
  defp decode({5, term}), do: term

  # Version 4 tanks were saved before hulls and turrets could turn: they point the
  # default way (direction 0, turret along the hull).
  defp decode({4, %Game{} = game}) do
    tanks =
      Map.new(game.tanks, fn {player_id, tank} ->
        {player_id, tank |> Map.put_new(:heading, 0) |> Map.put_new(:aim, nil)}
      end)

    %{game | tanks: tanks}
  end

  defp decode({4, term}), do: term

  # Version 3 games were saved before the maximum range existed: they get the default
  # of 5, as the human decided. Tanks already above it keep their range but can't
  # upgrade any more. Then on as version 4.
  defp decode({3, %Game{} = game}),
    do: decode({4, update_in(game.settings, &Map.put_new(&1, :max_range, 5))})

  defp decode({3, term}), do: term

  # Version 2 games were saved before action counts existed: they start from zero.
  # Then on as version 3.
  defp decode({2, %Game{} = game}), do: decode({3, Map.put_new(game, :action_counts, %{})})
  defp decode({2, term}), do: term

  # Version 1 games were saved before table settings existed: they get the defaults,
  # which are exactly the rules they were played with. Then on as version 2.
  defp decode({1, %Game{} = game}),
    do: decode({2, Map.put_new(game, :settings, Settings.defaults())})

  defp decode({1, term}), do: term
end
