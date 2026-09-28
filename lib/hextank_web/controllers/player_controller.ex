defmodule HextankWeb.PlayerController do
  @moduledoc """
  Pages that change who you are, so they need to write the session cookie (which a
  LiveView can't do): picking a nickname on your first visit, and rejoin links.
  """

  use HextankWeb, :controller

  alias Hextank.Players
  alias HextankWeb.{Messages, RejoinLink}

  @doc "The welcome page: pick a nickname."
  def new(conn, params) do
    form = Phoenix.Component.to_form(%{"nickname" => ""}, as: :player)
    render(conn, :new, form: form, return_to: safe_return_to(params["return_to"]))
  end

  @doc "Creates the player and remembers them in the session."
  def create(conn, %{"player" => %{"nickname" => nickname}} = params) do
    return_to = safe_return_to(params["return_to"])

    case Players.create(nickname) do
      {:ok, player} ->
        conn
        |> log_in(player)
        |> put_flash(:info, gettext("Welcome, %{name}!", name: player.nickname))
        |> redirect(to: return_to)

      {:error, reason} ->
        form = Phoenix.Component.to_form(%{"nickname" => nickname}, as: :player)

        conn
        |> put_flash(:error, Messages.error(reason))
        |> render(:new, form: form, return_to: return_to)
    end
  end

  @doc "Where banned players end up. A plain page: no websocket, nothing to do."
  def banned(conn, _params), do: render(conn, :banned)

  @doc "A rejoin link: log in as the player it belongs to."
  def rejoin(conn, %{"token" => token}) do
    case RejoinLink.verify(token) do
      {:ok, player} ->
        conn
        |> log_in(player)
        |> put_flash(:info, gettext("Welcome back, %{name}!", name: player.nickname))
        |> redirect(to: ~p"/")

      :error ->
        conn
        |> put_flash(:error, gettext("This rejoin link doesn't work anymore."))
        |> redirect(to: ~p"/welcome")
    end
  end

  # A fresh session id on every login, so an old cookie can't be reused.
  defp log_in(conn, player) do
    conn
    |> configure_session(renew: true)
    |> put_session("player_id", player.id)
  end

  # Only go back to a page of this site: "/tables/abc" is fine, "//evil.example" or
  # "https://evil.example" is not.
  defp safe_return_to("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: ~p"/", else: path
  end

  defp safe_return_to(_other), do: ~p"/"
end
