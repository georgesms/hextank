defmodule HextankWeb.RejoinLink do
  @moduledoc """
  A player's personal link to log back in from any device (see README, *Identity*).

  The token is signed with `Phoenix.Token` and holds `{player_id, token_version}`, so
  nothing extra is stored. Resetting the link bumps the player's `token_version`,
  which makes older tokens stop working.

  Treat tokens like passwords: never log them or show them to other players.
  """

  use HextankWeb, :verified_routes

  alias Hextank.{Player, Players}

  @salt "rejoin link"

  @doc "The full URL of a player's rejoin link."
  @spec link_url(Player.t()) :: String.t()
  def link_url(player), do: url(~p"/rejoin/#{token(player)}")

  @doc "A signed token for the player."
  @spec token(Player.t()) :: String.t()
  def token(player) do
    Phoenix.Token.sign(HextankWeb.Endpoint, @salt, {player.id, player.token_version})
  end

  @doc "The player a token belongs to, if the token is valid and wasn't reset."
  @spec verify(String.t()) :: {:ok, Player.t()} | :error
  def verify(token) do
    with {:ok, {player_id, version}} <-
           Phoenix.Token.verify(HextankWeb.Endpoint, @salt, token, max_age: :infinity),
         {:ok, %Player{token_version: ^version} = player} <- Players.get(player_id) do
      {:ok, player}
    else
      _ -> :error
    end
  end
end
