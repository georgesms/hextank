defmodule HextankWeb.LobbyLive do
  @moduledoc """
  The lobby: your tables, the public tables you can join, and a form to create a
  table. It reads only the `Lobby` summaries, never the games themselves.
  """

  use HextankWeb, :live_view

  alias Hextank.{Chat, Settings, Tables}
  alias HextankWeb.Messages

  import HextankWeb.GameComponents, only: [status_badge: 1]

  @impl true
  def mount(_params, _session, socket) do
    player = socket.assigns.current_player
    my_tables = Tables.list_for_player(player.id)
    my_ids = MapSet.new(my_tables, & &1.id)

    socket =
      socket
      |> assign(:page_title, gettext("Lobby"))
      |> assign(:my_tables, my_tables)
      # One small chat read per table you're in; public tables aren't read at all.
      |> assign(:unread, Map.new(my_tables, &{&1.id, Chat.unread_count(&1.id, player.id)}))
      |> assign(:open_tables, Enum.reject(Tables.list_public(), &(&1.id in my_ids)))
      |> assign(:form, new_table_form())
      |> assign(:rejoin_url, HextankWeb.RejoinLink.link_url(player))

    {:ok, socket}
  end

  defp new_table_form(params \\ %{}) do
    defaults = %{
      "name" => "",
      "visibility" => "public",
      "tick_interval" => "86400",
      "board_radius" => "auto",
      "obstacle_percent" => "10",
      "start_hp" => "3",
      "start_range" => "2"
    }

    to_form(Map.merge(defaults, params), as: :table)
  end

  @impl true
  def handle_event("create", %{"table" => params}, socket) do
    player = socket.assigns.current_player

    attrs = %{
      name: params["name"] || "",
      visibility: if(params["visibility"] == "private", do: :private, else: :public),
      tick_interval: parse_integer(params["tick_interval"]),
      settings: %{
        board_radius: parse_radius(params["board_radius"]),
        obstacle_percent: parse_integer(params["obstacle_percent"]),
        start_hp: parse_integer(params["start_hp"]),
        start_range: parse_integer(params["start_range"])
      }
    }

    case Tables.create_table(player, attrs) do
      {:ok, game} ->
        {:noreply, push_navigate(socket, to: ~p"/tables/#{game.id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> put_flash(:error, Messages.error(reason))
         |> assign(:form, new_table_form(params))}
    end
  end

  defp parse_radius("auto"), do: :auto
  defp parse_radius(value), do: parse_integer(value)

  # Unparseable values become nil, which Tables.create_table/4 rejects.
  defp parse_integer(value) do
    case Integer.parse(to_string(value)) do
      {seconds, ""} -> seconds
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} locale={@locale}>
      <div class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_22rem]">
        <div class="space-y-10">
          <section id="my-tables">
            <h2 class="text-xl font-bold tracking-tight">{gettext("Your tables")}</h2>
            <p :if={@my_tables == []} class="mt-2 text-base-content/60">
              {gettext("You're not at any table yet. Join one below or create your own.")}
            </p>
            <div class="mt-4 grid gap-3 sm:grid-cols-2">
              <.table_card
                :for={summary <- @my_tables}
                summary={summary}
                unread={@unread[summary.id]}
              />
            </div>
          </section>

          <section id="open-tables">
            <h2 class="text-xl font-bold tracking-tight">{gettext("Open tables")}</h2>
            <p :if={@open_tables == []} class="mt-2 text-base-content/60">
              {gettext("No public tables right now. Create one and invite your friends!")}
            </p>
            <div class="mt-4 grid gap-3 sm:grid-cols-2">
              <.table_card :for={summary <- @open_tables} summary={summary} />
            </div>
          </section>
        </div>

        <aside class="space-y-6">
          <.form
            for={@form}
            id="new-table-form"
            phx-submit="create"
            class="rounded-2xl border border-base-300 bg-base-200/60 p-5 shadow-sm"
          >
            <h2 class="mb-4 text-lg font-bold">{gettext("New table")}</h2>
            <.input
              field={@form[:name]}
              label={gettext("Name")}
              placeholder={gettext("Friday night tanks")}
              maxlength="40"
              autocomplete="off"
              required
            />
            <.input
              field={@form[:visibility]}
              type="select"
              label={gettext("Who can join")}
              options={[
                {gettext("Anyone (listed in the lobby)"), "public"},
                {gettext("Only people with the link"), "private"}
              ]}
            />
            <.input
              field={@form[:tick_interval]}
              type="select"
              label={gettext("Game speed")}
              options={for s <- Tables.tick_intervals(), do: {Messages.tick_interval(s), s}}
            />
            <details id="more-settings" class="mb-3">
              <summary class="cursor-pointer select-none py-1 text-sm font-semibold text-base-content/70 hover:text-base-content">
                {gettext("More settings")}
              </summary>
              <div class="mt-2">
                <.input
                  field={@form[:board_radius]}
                  type="select"
                  label={gettext("Board size")}
                  options={
                    for r <- Settings.allowed(:board_radius), do: {Messages.board_radius(r), r}
                  }
                />
                <.input
                  field={@form[:obstacle_percent]}
                  type="select"
                  label={gettext("Rocks")}
                  options={
                    for p <- Settings.allowed(:obstacle_percent), do: {Messages.obstacles(p), p}
                  }
                />
                <div class="grid grid-cols-2 gap-3">
                  <.input
                    field={@form[:start_hp]}
                    type="select"
                    label={gettext("Starting HP")}
                    options={Settings.allowed(:start_hp)}
                  />
                  <.input
                    field={@form[:start_range]}
                    type="select"
                    label={gettext("Starting range")}
                    options={Settings.allowed(:start_range)}
                  />
                </div>
              </div>
            </details>
            <button id="create-table" class="btn btn-primary mt-2 w-full">
              {gettext("Create table")}
            </button>
          </.form>

          <div class="rounded-2xl border border-info/30 bg-info/10 p-5 text-sm">
            <p class="font-semibold">{gettext("Playing on another device?")}</p>
            <p class="mt-1 text-base-content/70">
              {gettext("Your account page has a personal link that logs you back in anywhere.")}
            </p>
            <button
              id="show-rejoin-link"
              type="button"
              phx-click={Layouts.show_rejoin_modal("rejoin-modal")}
              class="link link-info mt-2 inline-block font-medium"
            >
              {gettext("Get my rejoin link")}
            </button>
          </div>
        </aside>
      </div>

      <Layouts.rejoin_modal id="rejoin-modal" url={@rejoin_url} />
    </Layouts.app>
    """
  end

  attr :summary, :map, required: true
  attr :unread, :integer, default: 0

  defp table_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/tables/#{@summary.id}"}
      id={"table-card-#{@summary.id}"}
      class="group block rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm transition hover:-translate-y-0.5 hover:border-primary/50 hover:shadow-md"
    >
      <div class="flex items-start justify-between gap-2">
        <h3 class="truncate font-semibold group-hover:text-primary">{@summary.name}</h3>
        <.status_badge status={@summary.status} />
      </div>
      <div class="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-base-content/60">
        <span class="flex items-center gap-1">
          <.icon name="hero-users-micro" class="size-4" />
          {length(@summary.player_ids)}/20
        </span>
        <span class="flex items-center gap-1">
          <.icon name="hero-clock-micro" class="size-4" />
          {Messages.tick_interval(@summary.tick_interval)}
        </span>
        <span
          :if={@unread > 0}
          id={"unread-#{@summary.id}"}
          class="flex items-center gap-1 font-semibold text-primary"
        >
          <.icon name="hero-chat-bubble-left-micro" class="size-4" />
          {ngettext("1 new message", "%{count} new messages", @unread)}
        </span>
        <span :if={@summary.visibility == :private} class="flex items-center gap-1">
          <.icon name="hero-lock-closed-micro" class="size-4" />
          {gettext("Private")}
        </span>
      </div>
    </.link>
    """
  end
end
