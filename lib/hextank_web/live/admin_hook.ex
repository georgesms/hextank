defmodule HextankWeb.AdminHook do
  @moduledoc """
  Lets only admins (see `Hextank.Admin.admin?/1`) mount a LiveView. Runs after
  `HextankWeb.PlayerHook`, which loads the player.

  The check runs on every mount, over HTTP and over the websocket, so the admin
  page can't be reached by skipping the router's plugs.
  """

  use Gettext, backend: HextankWeb.Gettext
  use HextankWeb, :verified_routes

  import Phoenix.LiveView, only: [put_flash: 3, redirect: 2]

  alias Hextank.Admin

  def on_mount(:default, _params, _session, socket) do
    if Admin.admin?(socket.assigns.current_player) do
      {:cont, socket}
    else
      socket = put_flash(socket, :error, gettext("That page is for admins only."))
      {:halt, redirect(socket, to: ~p"/")}
    end
  end
end
