defmodule HextankWeb.PlayerHook do
  @moduledoc """
  Runs when every LiveView mounts: sets the language and loads the current player
  from the session. LiveViews can't read plug assigns, so this repeats what the
  plugs did for the first page load.

  It also makes every page leave for `/banned` the moment its player is banned: it
  subscribes to `"player:<id>"` and attaches a `handle_info` hook for `:banned`, so no
  LiveView has to handle that itself.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1, redirect: 2]

  alias Hextank.Players.Bans

  use HextankWeb, :verified_routes

  alias Hextank.Players

  def on_mount(:default, _params, session, socket) do
    locale = session["locale"] || "en"
    Gettext.put_locale(HextankWeb.Gettext, locale)
    socket = assign(socket, :locale, locale)

    case Players.get(session["player_id"]) do
      {:ok, player} ->
        if Bans.banned?(player.id) do
          {:halt, redirect(socket, to: ~p"/banned")}
        else
          {:cont, socket |> assign(:current_player, player) |> leave_when_banned(player)}
        end

      {:error, :not_found} ->
        {:halt, redirect(socket, to: ~p"/welcome")}
    end
  end

  defp leave_when_banned(socket, player) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Hextank.PubSub, "player:#{player.id}")

      attach_hook(socket, :leave_when_banned, :handle_info, fn
        :banned, socket -> {:halt, redirect(socket, to: ~p"/banned")}
        _other, socket -> {:cont, socket}
      end)
    else
      socket
    end
  end
end
