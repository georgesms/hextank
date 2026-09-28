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
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="border-b border-base-300 bg-base-100/80 backdrop-blur">
      <div class="mx-auto flex max-w-6xl items-center gap-3 px-4 py-3 sm:px-6">
        <.link navigate={~p"/"} class="flex items-center gap-2 font-bold tracking-tight">
          <.hex_logo class="size-7" />
          <span class="text-lg">HexTank</span>
        </.link>

        <div class="ml-auto flex items-center gap-2 sm:gap-3">
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

    <main class="px-4 py-6 sm:px-6 sm:py-10">
      <div class="mx-auto max-w-6xl">
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc "The HexTank logo: a pointy-top hexagon with a tank turret."
  attr :class, :string, default: nil

  def hex_logo(assigns) do
    ~H"""
    <svg viewBox="-12 -12 24 24" class={@class} aria-hidden="true">
      <polygon
        points="0,-11 9.5,-5.5 9.5,5.5 0,11 -9.5,5.5 -9.5,-5.5"
        class="fill-primary"
      />
      <circle r="4" class="fill-primary-content" />
      <rect x="2" y="-1.2" width="7" height="2.4" rx="1" class="fill-primary-content" />
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
