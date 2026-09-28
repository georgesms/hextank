defmodule HextankWeb.Plugs.CurrentPlayer do
  @moduledoc """
  Loads the player whose id is in the session into `conn.assigns.current_player`
  (or `nil`).

  `require_player/2` sends visitors without a player to the welcome page, and brings
  them back to the page they asked for afterwards (so an invite link still works).
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  use HextankWeb, :verified_routes

  alias Hextank.Players

  def init(options), do: options

  def call(conn, _options) do
    player =
      case Players.get(get_session(conn, "player_id")) do
        {:ok, player} -> player
        {:error, :not_found} -> nil
      end

    assign(conn, :current_player, player)
  end

  @doc "A plug for routes that need a player."
  def require_player(%{assigns: %{current_player: nil}} = conn, _options) do
    return_to = current_path(conn)

    conn
    |> redirect(to: ~p"/welcome?#{[return_to: return_to]}")
    |> halt()
  end

  def require_player(conn, _options), do: conn

  defp current_path(%{query_string: ""} = conn), do: conn.request_path
  defp current_path(conn), do: conn.request_path <> "?" <> conn.query_string
end
