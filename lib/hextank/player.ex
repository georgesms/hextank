defmodule Hextank.Player do
  @moduledoc """
  A player: a random id and a nickname, no account (see README, *Identity*).

  Fields for later phases (`google_sub`, `strikes`, `banned_at`) are already here, so
  players saved now don't need a save-format upgrade later.
  """

  @enforce_keys [:id, :nickname, :created_at]
  defstruct [
    :id,
    :nickname,
    :created_at,
    # Bumped by "reset my rejoin link": links with an older version stop working.
    token_version: 1,
    # Phase 6: the linked Google account.
    google_sub: nil,
    # Phase 5: moderation.
    strikes: [],
    banned_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          nickname: String.t(),
          created_at: DateTime.t(),
          token_version: pos_integer(),
          google_sub: String.t() | nil,
          strikes: list(),
          banned_at: DateTime.t() | nil
        }

  # Letters (any language), digits, spaces, "_" and "-".
  @nickname_format ~r/\A[\p{L}\p{N} _-]+\z/u

  @doc """
  Checks a nickname: 2 to 20 characters, letters, digits, spaces, `_` and `-`.
  Returns it trimmed.

      iex> Player.validate_nickname("  Ana Júlia ")
      {:ok, "Ana Júlia"}

      iex> Player.validate_nickname("<script>")
      {:error, :invalid_nickname}
  """
  @spec validate_nickname(term()) :: {:ok, String.t()} | {:error, :invalid_nickname}
  def validate_nickname(nickname) when is_binary(nickname) do
    nickname = String.trim(nickname)

    if String.length(nickname) in 2..20 and Regex.match?(@nickname_format, nickname),
      do: {:ok, nickname},
      else: {:error, :invalid_nickname}
  end

  def validate_nickname(_nickname), do: {:error, :invalid_nickname}

  @doc """
  Records a strike for writing a prohibited word (see README, *Moderation*): the
  first is a warning, the second a final warning, the third a ban. Strikes never
  expire. `strike` says where it happened (`:table_id`) and which word matched
  (`:word`); the message itself is not kept.

      iex> player = %Player{id: "ana1234567", nickname: "Ana", created_at: ~U[2026-01-01 00:00:00Z]}
      iex> {player, :warning} = Player.add_strike(player, %{word: "badword"}, ~U[2026-01-02 00:00:00Z])
      iex> {player, :final_warning} = Player.add_strike(player, %{word: "badword"}, ~U[2026-01-03 00:00:00Z])
      iex> {player, :banned} = Player.add_strike(player, %{word: "badword"}, ~U[2026-01-04 00:00:00Z])
      iex> player.banned_at
      ~U[2026-01-04 00:00:00Z]
  """
  @spec add_strike(t(), map(), DateTime.t()) :: {t(), :warning | :final_warning | :banned}
  def add_strike(player, strike, now) do
    player = %{player | strikes: player.strikes ++ [Map.put(strike, :at, now)]}

    case length(player.strikes) do
      1 -> {player, :warning}
      2 -> {player, :final_warning}
      _ -> {%{player | banned_at: player.banned_at || now}, :banned}
    end
  end

  @doc "Whether the player is banned."
  @spec banned?(t()) :: boolean()
  def banned?(player), do: player.banned_at != nil

  @doc "Lifts a ban and clears the strikes."
  @spec unban(t()) :: t()
  def unban(player), do: %{player | banned_at: nil, strikes: []}
end
