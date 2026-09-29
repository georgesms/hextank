defmodule HextankWeb.Messages do
  @moduledoc """
  Turns what the game says (error atoms, events, durations) into text for players,
  in their language. Error reasons are translated here and nowhere else (see
  CLAUDE.md, *Translations*).
  """

  use Gettext, backend: HextankWeb.Gettext

  alias Hextank.Game

  @doc "The text for an error reason."
  @spec error(atom()) :: String.t()
  def error(:not_in_game), do: gettext("You're not playing at this table.")
  def error(:already_joined), do: gettext("You're already at this table.")
  def error(:table_full), do: gettext("This table is full.")
  def error(:game_already_started), do: gettext("The game has already started.")
  def error(:not_creator), do: gettext("Only the table's creator can start the game.")
  def error(:not_enough_players), do: gettext("A game needs at least 2 players.")
  def error(:game_not_running), do: gettext("The game isn't running.")
  def error(:not_enough_ap), do: gettext("You need 1 action point for that.")
  def error(:max_range_reached), do: gettext("Your range is already this table's maximum.")
  def error(:not_adjacent), do: gettext("You can only move to a neighbouring cell.")
  def error(:off_board), do: gettext("That's off the board.")
  def error(:obstacle), do: gettext("There's a rock there.")
  def error(:cell_occupied), do: gettext("There's a tank there.")
  def error(:cannot_target_self), do: gettext("You can't target yourself.")
  def error(:invalid_target), do: gettext("Pick a tank that's still on the board.")
  def error(:out_of_range), do: gettext("That tank is out of your range.")
  def error(:tank_destroyed), do: gettext("Your tank was destroyed.")
  def error(:not_a_ghost), do: gettext("Only ghosts can vote.")
  def error(:no_vote_left), do: gettext("You've already voted this round.")
  def error(:frozen), do: gettext("Your tank is frozen.")
  def error(:not_found), do: gettext("This table doesn't exist.")
  def error(:table_deleted), do: gettext("This table was deleted.")

  def error({:prohibited, :warning}),
    do: gettext("That text has a prohibited word, so it wasn't sent. Warning 1 of 2.")

  def error({:prohibited, :final_warning}),
    do:
      gettext(
        "That text has a prohibited word, so it wasn't sent. Final warning: next time you'll be banned."
      )

  def error({:prohibited, :banned}), do: gettext("You've been banned for hate speech.")
  def error(:banned), do: gettext("You've been banned.")
  def error(:inappropriate), do: gettext("Please pick different words.")
  def error(:empty_message), do: gettext("Write something first.")
  def error(:message_too_long), do: gettext("A message has at most 500 characters.")
  def error(:invalid_recipient), do: gettext("Pick another player of this table.")
  def error(:too_fast), do: gettext("Slow down: at most 5 messages in 10 seconds.")
  def error(:unreachable), do: gettext("There's no way to drive there.")
  def error(:invalid_settings), do: gettext("Those table settings aren't allowed.")
  def error(:board_too_small), do: gettext("The board is too small for this many players.")
  def error(:invalid_name), do: gettext("A table name has 3 to 40 characters.")
  def error(:invalid_nickname), do: gettext("A nickname has 2 to 20 letters, digits or spaces.")
  def error(_reason), do: gettext("Something went wrong.")

  @doc "One line of the event log."
  @spec event(Game.event(), Game.t()) :: String.t()
  def event(%{type: type} = event, game) do
    actor = name(game, event[:actor])
    target = name(game, event[:target])

    case type do
      :joined ->
        gettext("%{name} joined the table", name: actor)

      :left ->
        gettext("A player left the table")

      :started ->
        gettext("The game started!")

      :moved ->
        ngettext("%{name} moved 1 cell", "%{name} moved %{count} cells", event[:steps] || 1,
          name: actor
        )

      :shot ->
        gettext("%{name} shot %{target}", name: actor, target: target)

      :destroyed ->
        gettext("%{name} destroyed %{target}", name: actor, target: target)

      :upgraded ->
        gettext("%{name} upgraded their range", name: actor)

      :gave_ap ->
        gettext("%{name} gave 1 AP to %{target}", name: actor, target: target)

      # Ghost votes are anonymous: that's part of the politics.
      :voted ->
        gettext("A ghost gave 1 AP to %{target}", target: target)

      :won ->
        gettext("%{name} won the game!", name: actor)

      _other ->
        gettext("Something happened")
    end
  end

  defp name(_game, nil), do: nil

  defp name(game, player_id) do
    case Game.tank(game, player_id) do
      nil -> gettext("someone")
      tank -> tank.name
    end
  end

  @doc """
  A tank's stats on two lines, for the hover tooltip: "Ana" then
  "❤️❤️❤️ · ⚡⚡ · 🎯🎯" (HP, AP and range, see `GameComponents.stat_text/2`).
  """
  @spec tank_stats(Hextank.Tank.t()) :: String.t()
  def tank_stats(tank) do
    stats =
      Enum.map_join([hp: tank.hp, ap: tank.ap, range: tank.range], " · ", fn {kind, count} ->
        HextankWeb.GameComponents.stat_text(kind, count)
      end)

    frozen = if tank.frozen, do: " · " <> gettext("frozen"), else: ""
    tank.name <> "\n" <> stats <> frozen
  end

  @doc "How often AP arrives, e.g. \"1 AP per day\"."
  @spec tick_interval(pos_integer()) :: String.t()
  def tick_interval(10), do: gettext("1 AP every 10 seconds")
  def tick_interval(60), do: gettext("1 AP per minute")
  def tick_interval(3_600), do: gettext("1 AP per hour")
  def tick_interval(86_400), do: gettext("1 AP per day")
  def tick_interval(seconds), do: gettext("1 AP every %{time}", time: duration(seconds))

  @doc """
  A short duration: "42 s", "5 min", "3 h 12 min".
  """
  @spec duration(integer()) :: String.t()
  def duration(seconds) when seconds < 60, do: gettext("%{s} s", s: max(seconds, 0))
  def duration(seconds) when seconds < 3_600, do: gettext("%{m} min", m: div(seconds, 60))

  def duration(seconds) do
    gettext("%{h} h %{m} min", h: div(seconds, 3_600), m: div(rem(seconds, 3_600), 60))
  end

  @doc "How long ago something happened: \"just now\", \"5 min ago\"."
  @spec ago(integer()) :: String.t()
  def ago(seconds) when seconds < 60, do: gettext("just now")
  def ago(seconds), do: gettext("%{time} ago", time: duration(seconds))

  @doc """
  How long ago a game started, in whole days: "Started 3 days ago", or "Started less
  than a day ago".
  """
  @spec started_ago(integer()) :: String.t()
  def started_ago(seconds) when seconds < 86_400, do: gettext("Started less than a day ago")

  def started_ago(seconds) do
    days = div(seconds, 86_400)
    ngettext("Started 1 day ago", "Started %{count} days ago", days)
  end

  @doc """
  How long until a table is deleted, in days, rounded up: "Deleted in 5 days". Never
  less than 1 day, so it doesn't say "0 days" in its last hours.
  """
  @spec deleted_in(integer()) :: String.t()
  def deleted_in(seconds) do
    days = max(div(seconds + 86_399, 86_400), 1)
    ngettext("Deleted in 1 day", "Deleted in %{count} days", days)
  end

  @doc "The label of a board size setting."
  @spec board_radius(:auto | pos_integer()) :: String.t()
  def board_radius(:auto), do: gettext("Automatic (grows with players)")

  def board_radius(radius) do
    gettext("Radius %{radius} (%{cells} cells)",
      radius: radius,
      cells: Hextank.Board.cell_count(radius)
    )
  end

  @doc "The label of a rocks setting."
  @spec obstacles(non_neg_integer()) :: String.t()
  def obstacles(0), do: gettext("None")
  def obstacles(5), do: gettext("Few (5%)")
  def obstacles(10), do: gettext("Normal (10%)")
  def obstacles(percent), do: gettext("Many (%{percent}%)", percent: percent)

  @doc "The label of a maximum range setting."
  @spec max_range(pos_integer() | :none) :: String.t()
  def max_range(:none), do: gettext("No limit")
  def max_range(range), do: to_string(range)

  @doc "A table's settings as {label, value} pairs, for showing them."
  @spec settings_summary(Hextank.Settings.t()) :: [{String.t(), String.t()}]
  def settings_summary(settings) do
    [
      {gettext("Board size"), board_radius(settings.board_radius)},
      {gettext("Rocks"), obstacles(settings.obstacle_percent)},
      {gettext("Starting HP"), to_string(settings.start_hp)},
      {gettext("Starting range"), to_string(settings.start_range)},
      {gettext("Maximum range"), max_range(settings.max_range)}
    ]
  end

  @doc "A game's status, for badges."
  @spec status(Game.status()) :: String.t()
  def status(:lobby), do: gettext("Not started")
  def status(:running), do: gettext("Running")
  def status(:finished), do: gettext("Finished")
end
