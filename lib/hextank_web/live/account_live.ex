defmodule HextankWeb.AccountLive do
  @moduledoc """
  Your nickname and your rejoin link: the personal link that logs you back in on
  any device (see README, *Identity*).
  """

  use HextankWeb, :live_view

  alias Hextank.Players
  alias HextankWeb.{Messages, RejoinLink}

  @impl true
  def mount(_params, _session, socket) do
    player = socket.assigns.current_player

    socket =
      socket
      |> assign(:page_title, gettext("Account"))
      |> assign(:form, to_form(%{"nickname" => player.nickname}, as: :player))
      |> assign(:rejoin_url, RejoinLink.link_url(player))

    {:ok, socket}
  end

  @impl true
  def handle_event("rename", %{"player" => %{"nickname" => nickname}}, socket) do
    case Players.rename(socket.assigns.current_player, nickname) do
      {:ok, player} ->
        {:noreply,
         socket
         |> assign(:current_player, player)
         |> put_flash(:info, gettext("Nickname changed."))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Messages.error(reason))}
    end
  end

  def handle_event("reset-link", _params, socket) do
    {:ok, player} = Players.reset_rejoin_link(socket.assigns.current_player)

    {:noreply,
     socket
     |> assign(:current_player, player)
     |> assign(:rejoin_url, RejoinLink.link_url(player))
     |> put_flash(:info, gettext("New link created. The old one no longer works."))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} locale={@locale}>
      <div class="mx-auto max-w-xl space-y-6">
        <h1 class="text-2xl font-bold tracking-tight">{gettext("Account")}</h1>

        <section class="rounded-2xl border border-base-300 bg-base-200/60 p-5">
          <h2 class="font-bold">{gettext("Your rejoin link")}</h2>
          <p class="mt-1 text-sm text-base-content/70">
            {gettext(
              "Bookmark this link or keep it somewhere safe: it logs you back in as yourself on any device. It works like a password, so don't share it."
            )}
          </p>
          <div class="mt-3">
            <Layouts.rejoin_link_field id="rejoin-link" url={@rejoin_url} />
          </div>
          <button
            id="reset-link"
            phx-click="reset-link"
            data-confirm={gettext("The current link will stop working. Continue?")}
            class="btn btn-ghost btn-sm mt-3"
          >
            {gettext("Someone else has my link: make a new one")}
          </button>
        </section>

        <.form
          for={@form}
          id="rename-form"
          phx-submit="rename"
          class="rounded-2xl border border-base-300 p-5"
        >
          <h2 class="mb-3 font-bold">{gettext("Nickname")}</h2>
          <.input field={@form[:nickname]} maxlength="20" autocomplete="off" required />
          <p class="-mt-1 mb-3 text-xs text-base-content/60">
            {gettext("Tanks already on a board keep the name they joined with.")}
          </p>
          <button class="btn btn-primary">{gettext("Save")}</button>
        </.form>

        <p id="player-id" class="text-xs text-base-content/50">
          {gettext("Your player id: %{id}. It isn't secret; the site's admins use it.",
            id: @current_player.id
          )}
        </p>
      </div>
    </Layouts.app>
    """
  end
end
