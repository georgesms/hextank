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
end
