defmodule HextankWeb.Plugs.Locale do
  @moduledoc """
  Picks the language for the request and remembers it in the session, where the
  LiveViews read it too.

  In order: a `?locale=` link (the switch in the header), the session, the browser's
  `Accept-Language` header, English.
  """

  import Plug.Conn

  @locales ["en", "pt_BR"]

  @doc "The supported locales."
  def locales, do: @locales

  def init(options), do: options

  def call(conn, _options) do
    locale =
      known(conn.params["locale"]) ||
        known(get_session(conn, "locale")) ||
        from_header(conn) ||
        "en"

    Gettext.put_locale(HextankWeb.Gettext, locale)

    # Writing the session on every request also sends the session cookie again, with
    # a fresh year of `max_age`: a player who keeps playing is never logged out.
    conn
    |> put_session("locale", locale)
    |> assign(:locale, locale)
  end

  defp known(locale) when locale in @locales, do: locale
  defp known(_locale), do: nil

  defp from_header(conn) do
    case get_req_header(conn, "accept-language") do
      [value | _] -> if String.starts_with?(String.downcase(value), "pt"), do: "pt_BR"
      [] -> nil
    end
  end
end
