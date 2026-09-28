defmodule HextankWeb.AdminLive do
  @moduledoc """
  The admin page: statistics about tables, players, actions and chat, and a list of
  every table to delete several at once. Only admins get here (`HextankWeb.AdminHook`).

  The numbers are worked out when the page opens and when "Refresh" is pressed,
  never on a timer (see `Hextank.Admin`).
  """

  use HextankWeb, :live_view

  alias Hextank.Admin
  alias HextankWeb.Messages

  import HextankWeb.GameComponents, only: [status_badge: 1]

  @filters ~w(all lobby running finished)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: gettext("Admin"), filter: "all", selected: MapSet.new())
      |> load()

    {:ok, socket}
  end

  defp load(socket) do
    now = DateTime.utc_now()
    tables = Admin.tables()

    socket
    |> assign(
      now: now,
      tables: tables,
      stats: Admin.table_stats(tables, now),
      server: Admin.server_stats()
    )
    |> assign_shown()
  end

  # The tables the filter lets through. Only those can stay selected.
  defp assign_shown(socket) do
    %{tables: tables, filter: filter, selected: selected} = socket.assigns

    shown =
      if filter == "all", do: tables, else: Enum.filter(tables, &(to_string(&1.status) == filter))

    shown_ids = MapSet.new(shown, & &1.id)
    assign(socket, shown: shown, selected: MapSet.intersection(selected, shown_ids))
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load(socket)}

  def handle_event("filter", %{"status" => status}, socket) when status in @filters do
    {:noreply, socket |> assign(:filter, status) |> assign_shown()}
  end

  # The checkboxes: the browser sends the ids of every checked one.
  def handle_event("select", params, socket) do
    {:noreply, socket |> assign(:selected, MapSet.new(params["ids"] || [])) |> assign_shown()}
  end

  def handle_event("select_all", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new(socket.assigns.shown, & &1.id))}
  end

  def handle_event("select_none", _params, socket) do
    {:noreply, assign(socket, :selected, MapSet.new())}
  end

  def handle_event("delete", _params, socket) do
    count = socket.assigns.selected |> MapSet.to_list() |> Admin.delete_tables()

    {:noreply,
     socket
     |> put_flash(:info, ngettext("Deleted 1 table.", "Deleted %{count} tables.", count))
     |> assign(:selected, MapSet.new())
     |> load()}
  end

  ## Page

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_player={@current_player} locale={@locale}>
      <div class="space-y-8">
        <div class="flex flex-wrap items-center gap-3">
          <h1 class="text-2xl font-bold tracking-tight">{gettext("Admin")}</h1>
          <button id="refresh" phx-click="refresh" class="btn btn-sm ml-auto gap-1.5">
            <.icon name="hero-arrow-path-micro" class="size-4" /> {gettext("Refresh")}
          </button>
        </div>

        <div id="stats" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <.stat_card id="stats-tables" title={gettext("Tables")} value={@stats.total}>
            <:line>{gettext("Waiting")}: {@stats.by_status.lobby}</:line>
            <:line>{gettext("Running")}: {@stats.by_status.running}</:line>
            <:line>{gettext("Finished")}: {@stats.by_status.finished}</:line>
            <:line>{gettext("Public tables")}: {@stats.public}</:line>
            <:line>{gettext("Private tables")}: {@stats.total - @stats.public}</:line>
          </.stat_card>

          <.stat_card id="stats-players" title={gettext("Players")} value={@server.players}>
            <:line>{gettext("At a table")}: {@stats.seated_players}</:line>
            <:line>{gettext("Banned")}: {@server.banned}</:line>
          </.stat_card>

          <.stat_card
            id="stats-actions"
            title={gettext("Actions")}
            value={@stats.actions |> Map.values() |> Enum.sum()}
          >
            <:line :for={{kind, label} <- action_labels()}>
              {label}: {Map.get(@stats.actions, kind, 0)}
            </:line>
          </.stat_card>

          <.stat_card id="stats-chat" title={gettext("Chat")} value={format_bytes(@stats.chat_bytes)}>
            <:line>{gettext("Tables with messages")}: {@stats.tables_with_chat}</:line>
            <:line>{gettext("Tables awake")}: {@server.awake_tables}</:line>
            <:line>{gettext("Server memory")}: {format_bytes(@server.memory_bytes)}</:line>
          </.stat_card>
        </div>

        <section class="rounded-2xl border border-base-300 p-5">
          <div class="flex flex-wrap items-baseline gap-x-4 gap-y-1">
            <h2 class="font-bold">{gettext("New tables per day")}</h2>
            <p class="text-sm text-base-content/60">
              {gettext("%{day} today · %{week} this week · %{month} in 30 days",
                day: @stats.created_last_day,
                week: @stats.created_last_week,
                month: @stats.created_last_month
              )}
            </p>
          </div>
          <.day_chart days={@stats.created_per_day} />
        </section>

        <section class="rounded-2xl border border-base-300 p-5">
          <div class="flex flex-wrap items-center gap-2">
            <h2 class="mr-auto font-bold">{gettext("All tables")}</h2>
            <form id="filter-form" phx-change="filter">
              <select name="status" class="select select-bordered select-sm">
                <option
                  :for={{value, label} <- filter_options()}
                  value={value}
                  selected={@filter == value}
                >
                  {label}
                </option>
              </select>
            </form>
            <button id="select-all" phx-click="select_all" class="btn btn-ghost btn-sm">
              {gettext("Select all")}
            </button>
            <button id="select-none" phx-click="select_none" class="btn btn-ghost btn-sm">
              {gettext("Select none")}
            </button>
            <button
              id="delete-selected"
              phx-click="delete"
              disabled={MapSet.size(@selected) == 0}
              data-confirm={
                ngettext(
                  "Delete 1 table for good? Its game and chat are gone for everyone.",
                  "Delete %{count} tables for good? Their games and chats are gone for everyone.",
                  MapSet.size(@selected)
                )
              }
              class="btn btn-error btn-sm"
            >
              {gettext("Delete selected (%{count})", count: MapSet.size(@selected))}
            </button>
          </div>

          <p :if={@shown == []} id="no-tables" class="mt-4 text-sm text-base-content/60">
            {gettext("No tables here.")}
          </p>

          <form :if={@shown != []} id="tables-form" phx-change="select" class="mt-4 overflow-x-auto">
            <table class="table table-sm">
              <thead>
                <tr>
                  <th></th>
                  <th>{gettext("Name")}</th>
                  <th>{gettext("Status")}</th>
                  <th>{gettext("Players")}</th>
                  <th>{gettext("Actions")}</th>
                  <th>{gettext("Chat")}</th>
                  <th>{gettext("Created")}</th>
                </tr>
              </thead>
              <tbody id="tables">
                <tr :for={table <- @shown} :key={table.id} id={"table-#{table.id}"}>
                  <td>
                    <input
                      type="checkbox"
                      name="ids[]"
                      value={table.id}
                      checked={MapSet.member?(@selected, table.id)}
                      aria-label={gettext("Select %{name}", name: table.name)}
                      class="checkbox checkbox-sm"
                    />
                  </td>
                  <td class="max-w-56 truncate">
                    <.link navigate={~p"/tables/#{table.id}"} class="link link-hover font-medium">
                      {table.name}
                    </.link>
                    <span :if={table.visibility == :private} class="text-xs text-base-content/50">
                      · {gettext("Private")}
                    </span>
                  </td>
                  <td class="whitespace-nowrap"><.status_badge status={table.status} /></td>
                  <td>{length(table.player_ids)}</td>
                  <td>{table.action_counts |> Map.values() |> Enum.sum()}</td>
                  <td class="whitespace-nowrap">{format_bytes(table.chat_bytes)}</td>
                  <td class="whitespace-nowrap text-base-content/60">
                    {Messages.ago(DateTime.diff(@now, table.created_at, :second))}
                  </td>
                </tr>
              </tbody>
            </table>
          </form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :value, :any, required: true
  slot :line

  defp stat_card(assigns) do
    ~H"""
    <div id={@id} class="rounded-2xl border border-base-300 bg-base-200/60 p-4">
      <p class="text-sm text-base-content/60">{@title}</p>
      <p class="text-3xl font-bold tabular-nums">{@value}</p>
      <ul class="mt-2 space-y-0.5 text-sm text-base-content/70">
        <li :for={line <- @line}>{render_slot(line)}</li>
      </ul>
    </div>
    """
  end

  # One bar per day, as tall as that day's count compared to the busiest day.
  attr :days, :list, required: true

  defp day_chart(assigns) do
    assigns =
      assign(assigns, :most, assigns.days |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end))

    ~H"""
    <div id="day-chart" class="mt-4 flex h-32 items-end gap-1.5">
      <div
        :for={{date, count} <- @days}
        class="flex h-full flex-1 flex-col items-center justify-end gap-1"
        title={"#{Date.to_iso8601(date)}: #{count}"}
      >
        <span class="text-xs tabular-nums text-base-content/60">{count}</span>
        <div
          class="w-full rounded-t bg-primary/70"
          style={"height: #{if @most > 0, do: round(count / @most * 100), else: 0}%"}
        />
        <span class="text-[10px] tabular-nums text-base-content/50">{date.day}</span>
      </div>
    </div>
    """
  end

  defp action_labels do
    [
      move: gettext("Moves"),
      shoot: gettext("Shots"),
      give_ap: gettext("AP given"),
      upgrade_range: gettext("Range upgrades"),
      vote: gettext("Ghost votes")
    ]
  end

  defp filter_options do
    [
      {"all", gettext("All")},
      {"lobby", Messages.status(:lobby)},
      {"running", Messages.status(:running)},
      {"finished", Messages.status(:finished)}
    ]
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
