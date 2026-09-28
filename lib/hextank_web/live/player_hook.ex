defmodule HextankWeb.PlayerHook do
  @moduledoc """
  Runs when every LiveView mounts: sets the language and loads the current player
  from the session. LiveViews can't read plug assigns, so this repeats what the
  plugs did for the first page load.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  use HextankWeb, :verified_routes

  alias Hextank.Players

  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || "en"
    Gettext.put_locale(HextankWeb.Gettext, locale)
    socket = assign(socket, :locale, locale)

    case Players.get(session["player_id"]) do
      {:ok, player} -> {:cont, assign(socket, :current_player, player)}
      {:error, :not_found} -> {:halt, redirect(socket, to: ~p"/welcome")}
    end
  end
end
