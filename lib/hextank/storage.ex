defmodule Hextank.Storage do
  @moduledoc """
  All reading and writing of files (see README, *Architecture*). Nothing else in
  the app touches `File`.

  Data lives under the `:data_dir` config, one folder per table:

      tables/<id>/game.bin    the %Game{}, rewritten after every change

  Terms are saved with `:erlang.term_to_binary/1`, wrapped as `{version, term}` so a
  future change to the shape of `%Game{}` can still read old files (see CLAUDE.md,
  *Deployment rules*).
  """

  alias Hextank.Game

  @format_version 1

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

  ## Paths

  defp data_dir, do: Application.fetch_env!(:hextank, :data_dir)
  defp tables_dir, do: Path.join(data_dir(), "tables")

  defp table_dir(id) do
    if not valid_id?(id), do: raise(ArgumentError, "invalid id: #{inspect(id)}")
    Path.join(tables_dir(), id)
  end

  defp table_file(id, name), do: Path.join(table_dir(id), name)

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
  defp decode({1, term}), do: term
end
