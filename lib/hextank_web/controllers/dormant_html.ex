defmodule HextankWeb.DormantHTML do
  @moduledoc "Templates for `HextankWeb.DormantController`."

  use HextankWeb, :html

  import HextankWeb.GameComponents, only: [status_badge: 1]

  embed_templates "dormant_html/*"
end
