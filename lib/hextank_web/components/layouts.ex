defmodule HextankWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HextankWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  The page frame: header, content and flash messages. Every page starts with it.

      <Layouts.app flash={@flash} current_player={@current_player} locale={@locale}>
        <h1>Content</h1>
      </Layouts.app>
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_player, :any, default: nil, doc: "the %Player{} using the page, if any"
  attr :locale, :string, default: "en"

  attr :dormant_url, :string,
    default: nil,
    doc: "where app.js sends this tab once it's left alone (see DormantController)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-base-300 bg-base-100/80 backdrop-blur">
      <div class="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3 sm:px-6">
        <.link navigate={~p"/"} class="flex items-center gap-2">
          <.hex_logo class="size-8" />
          <span class="font-display text-xl tracking-wider">HEXTANK</span>
        </.link>

        <div class="ml-auto flex items-center gap-2 sm:gap-3">
          <button
            type="button"
            id="rules-button"
            popovertarget="rules"
            title={gettext("How to play")}
            aria-label={gettext("How to play")}
            class="flex rounded-full p-1.5 transition hover:bg-base-200"
          >
            <.icon name="hero-information-circle" class="size-6 opacity-80" />
          </button>
          <.link
            :if={Hextank.Admin.admin?(@current_player)}
            navigate={~p"/admin"}
            id="admin-link"
            class="rounded-full px-3 py-1.5 text-sm font-medium transition hover:bg-base-200"
          >
            {gettext("Admin")}
          </.link>
          <.link
            :if={@current_player}
            navigate={~p"/account"}
            id="account-link"
            class="flex items-center gap-1.5 rounded-full px-3 py-1.5 text-sm font-medium transition hover:bg-base-200"
          >
            <.icon name="hero-user-circle" class="size-5 opacity-70" />
            <span class="hidden max-w-32 truncate sm:inline">{@current_player.nickname}</span>
          </.link>

          <nav class="flex rounded-full border border-base-300 p-0.5 text-xs font-semibold">
            <a
              :for={{locale, label} <- [{"en", "EN"}, {"pt_BR", "PT"}]}
              href={"?locale=#{locale}"}
              id={"locale-#{locale}"}
              class={[
                "rounded-full px-2.5 py-1 transition",
                if(@locale == locale,
                  do: "bg-base-content text-base-100",
                  else: "opacity-60 hover:opacity-100"
                )
              ]}
            >
              {label}
            </a>
          </nav>

          <div class="hidden sm:block"><.theme_toggle /></div>
        </div>
      </div>
    </header>

    <main class="px-4 py-6 sm:px-6 sm:py-10" data-dormant-url={@dormant_url}>
      <div class="mx-auto max-w-6xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />

    <.rules />

    <.rejoin_modal
      :if={@current_player && Phoenix.Flash.get(@flash, :rejoin_link)}
      id="welcome-rejoin-modal"
      url={HextankWeb.RejoinLink.link_url(@current_player)}
      open
    />
    """
  end

  @doc """
  The rules in a few lines, opened by the info button in the header. A native HTML
  popover: the browser opens and closes it (Esc or a click outside closes it too),
  so it needs no JavaScript of ours and works on the dormant pages. LiveView leaves
  it alone (`phx-update="ignore"`), so a game update never closes it.
  """
  def rules(assigns) do
    ~H"""
    <div
      id="rules"
      popover
      phx-update="ignore"
      aria-labelledby="rules-title"
      class="m-auto max-h-[85vh] w-[min(34rem,calc(100vw-2rem))] overflow-y-auto rounded-box border border-base-300 bg-base-100 p-6 text-base-content shadow-xl backdrop:bg-black/50"
    >
      <h2 id="rules-title" class="text-xl">{gettext("How to play")}</h2>
      <ul class="mt-3 list-disc space-y-1.5 pl-5 text-sm">
        <li>
          {gettext("Tanks start with ❤️ 3 HP, 🎯 range 2 and ⚡ 0 AP, unless the table says otherwise.")}
        </li>
        <li>
          {gettext("Every living tank gets 1 ⚡ AP each round (the table sets how long a round is).")}
        </li>
        <li>
          {gettext(
            "Each action costs 1 ⚡: drive 1 cell, shoot a tank in range (1 damage), give it 1 ⚡, or add 1 🎯 to your range (up to the table's limit)."
          )}
        </li>
        <li>
          {gettext(
            "You only see up to twice your 🎯 range, and only drive where you can see. The rest of the board is fog."
          )}
        </li>
        <li>
          {gettext(
            "At 0 ❤️ you become a ghost and see the whole board: once a round you give 1 ⚡ to any living tank, and nobody knows it was you."
          )}
        </li>
        <li>{gettext("The last tank standing wins. Make alliances in the chat, and break them.")}</li>
      </ul>
      <h3 class="mt-5 font-semibold">{gettext("On the board")}</h3>
      <ul class="mt-2 list-disc space-y-1.5 pl-5 text-sm">
        <li>{gettext("Click a cell to see the path and its cost; click again to drive there.")}</li>
        <li>
          {gettext(
            "Click a tank to see if it's in range; double-click to shoot it (or give it AP, as chosen in your panel)."
          )}
        </li>
        <li>{gettext("Click your own tank to see your range; double-click it for range +1.")}</li>
        <li>{gettext("The buttons in the Your tank panel do the same. Esc cancels.")}</li>
      </ul>
      <div class="mt-6 flex justify-end">
        <button
          type="button"
          id="rules-close"
          popovertarget="rules"
          popovertargetaction="hide"
          class="btn btn-primary btn-sm"
        >
          {gettext("Got it")}
        </button>
      </div>
    </div>
    """
  end

  @doc """
  A modal asking players to save their rejoin link, so they don't lose their player.
  It opens by itself after signing up (the `:rejoin_link` flash, see `app/1`), or
  with `show_rejoin_modal/1`.
  """
  attr :id, :string, required: true
  attr :url, :string, required: true, doc: "the player's own rejoin link"
  attr :open, :boolean, default: false

  def rejoin_modal(assigns) do
    ~H"""
    <div
      id={@id}
      class={["modal", @open && "modal-open"]}
      role="dialog"
      aria-modal="true"
      aria-labelledby={"#{@id}-title"}
      phx-window-keydown={hide_rejoin_modal(@id)}
      phx-key="escape"
    >
      <div class="modal-box space-y-3">
        <h2 id={"#{@id}-title"} class="text-lg font-bold">
          {gettext("Save your rejoin link")}
        </h2>
        <p class="text-sm text-base-content/70">
          {gettext(
            "This link is your key: it logs you back in as yourself on any device, even if this browser forgets you. Keep it somewhere safe, like your notes or a message to yourself. It works like a password, so don't share it."
          )}
        </p>
        <.rejoin_link_field id={"#{@id}-link"} url={@url} />
        <p class="text-xs text-base-content/60">
          {gettext("You can find it again on your account page.")}
        </p>
        <div class="modal-action">
          <button id={"#{@id}-done"} type="button" class="btn" phx-click={hide_rejoin_modal(@id)}>
            {gettext("Done")}
          </button>
        </div>
      </div>
      <div class="modal-backdrop" phx-click={hide_rejoin_modal(@id)}></div>
    </div>
    """
  end

  @doc "Opens a `rejoin_modal/1`."
  def show_rejoin_modal(id) do
    JS.add_class("modal-open", to: "##{id}") |> JS.focus_first(to: "##{id}")
  end

  # Also drops the flash that opened it after signing up.
  defp hide_rejoin_modal(id) do
    JS.remove_class("modal-open", to: "##{id}")
    |> JS.push("lv:clear-flash", value: %{key: "rejoin_link"})
  end

  @doc """
  A player's rejoin link in a read-only field, with a button that copies it. Render it
  only on that player's own pages: the link works like a password.
  """
  attr :id, :string, required: true
  attr :url, :string, required: true

  def rejoin_link_field(assigns) do
    ~H"""
    <div class="flex gap-2">
      <input
        id={@id}
        readonly
        value={@url}
        class="input input-bordered w-full font-mono text-xs"
      />
      <button
        id={"copy-#{@id}"}
        type="button"
        class="btn btn-primary"
        phx-click={
          JS.dispatch("phx:copy", to: "##{@id}")
          |> JS.hide(to: "#copy-#{@id} .copy-label")
          |> JS.show(to: "#copy-#{@id} .copied-label", display: "inline-flex")
        }
      >
        <span class="copy-label inline-flex items-center gap-1">
          <.icon name="hero-clipboard-document" class="size-5" /> {gettext("Copy")}
        </span>
        <span class="copied-label hidden items-center gap-1">
          <.icon name="hero-check" class="size-5" /> {gettext("Copied!")}
        </span>
      </button>
    </div>
    """
  end

  @doc """
  The HexTank logo: a pointy-top hexagon as a gun sight, with the NATO symbol for
  armour inside. `priv/static/favicon.svg` is the same drawing in fixed colours.
  """
  attr :class, :string, default: nil

  def hex_logo(assigns) do
    ~H"""
    <svg viewBox="0 0 120 120" class={@class} aria-hidden="true">
      <polygon
        points="60,14 99.8,37 99.8,83 60,106 20.2,83 20.2,37"
        class="fill-none stroke-base-content"
        stroke-width="7"
      />
      <g class="stroke-base-content" stroke-width="7">
        <line x1="60" y1="14" x2="60" y2="2" />
        <line x1="99.8" y1="83" x2="110.2" y2="89" />
        <line x1="20.2" y1="83" x2="9.8" y2="89" />
      </g>
      <g class="fill-none stroke-primary" stroke-width="8">
        <rect x="35" y="46" width="50" height="29" />
        <ellipse cx="60" cy="60.5" rx="14" ry="6.5" />
      </g>
    </svg>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
