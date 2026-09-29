defmodule HextankWeb.DormantController do
  @moduledoc """
  Where a tab left alone ends up (see README, *Dormant view*). After 5 minutes hidden
  or 30 minutes without a click, key or scroll, `app.js` sends the browser here. It's
  a plain page load, so the LiveView and its websocket close, and with no open
  connection Fly can stop the machine.

  These pages must stay cheap: they read only the `Lobby` summary (never the game,
  never the table process) and their layout doesn't load `app.js`, so they open no
  websocket either.
  """

  use HextankWeb, :controller

  alias Hextank.Tables

  # The root layout leaves out app.js when :dormant is set.
  plug :put_dormant

  @doc "The lobby's dormant page, also used by the account and admin pages."
  def lobby(conn, _params), do: render(conn, :lobby)

  @doc "A table's dormant page. An unknown table gets the lobby's."
  def table(conn, %{"id" => id}) do
    case Tables.summary(id) do
      nil -> render(conn, :lobby)
      summary -> render(conn, :table, summary: summary)
    end
  end

  defp put_dormant(conn, _options), do: assign(conn, :dormant, true)
end
