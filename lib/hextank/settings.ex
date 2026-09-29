defmodule Hextank.Settings do
  @moduledoc """
  The settings a table's creator can choose (besides the tick interval, which lives on
  `%Game{}` itself): board size, how many rocks, each tank's starting HP, range and
  AP, and the highest range a tank can upgrade to. Chosen when the table is created, fixed
  afterwards.
  """

  @defaults %{
    board_radius: :auto,
    obstacle_percent: 10,
    start_hp: 3,
    start_range: 2,
    start_ap: 0,
    max_range: 5
  }

  @allowed %{
    # :auto grows the board with the number of players (see Board.radius_for/1).
    board_radius: [:auto | Enum.to_list(3..12)] ++ [14, 16, 18],
    obstacle_percent: [0, 5, 10, 20],
    start_hp: Enum.to_list(1..5),
    start_range: Enum.to_list(1..4),
    start_ap: [0, 1, 2, 3, 5, 10],
    # :none lets range grow without a limit.
    max_range: [4, 5, 6, 8, :none]
  }

  @type t :: %{
          board_radius: :auto | pos_integer(),
          obstacle_percent: non_neg_integer(),
          start_hp: pos_integer(),
          start_range: pos_integer(),
          start_ap: non_neg_integer(),
          max_range: pos_integer() | :none
        }

  @doc """
  The standard settings.

      iex> Settings.defaults().start_hp
      3
  """
  @spec defaults() :: t()
  def defaults, do: @defaults

  @doc "The allowed values of one setting, in order."
  @spec allowed(atom()) :: list()
  def allowed(key), do: Map.fetch!(@allowed, key)

  @doc """
  Fills in the defaults for anything missing, and checks every value is allowed. (The
  smallest maximum range is the largest starting range, so they always fit.)

      iex> Settings.validate(%{start_hp: 5})
      {:ok,
       %{
         board_radius: :auto,
         max_range: 5,
         obstacle_percent: 10,
         start_ap: 0,
         start_hp: 5,
         start_range: 2
       }}

      iex> Settings.validate(%{start_hp: 99})
      {:error, :invalid_settings}
  """
  @spec validate(map()) :: {:ok, t()} | {:error, :invalid_settings}
  def validate(settings) do
    settings = Map.merge(@defaults, Map.take(settings, Map.keys(@defaults)))

    if Enum.all?(settings, fn {key, value} -> value in allowed(key) end),
      do: {:ok, settings},
      else: {:error, :invalid_settings}
  end

  @doc """
  Whether a range is at most the maximum (always, with no maximum).

      iex> Settings.within_max_range?(5, 5)
      true

      iex> Settings.within_max_range?(6, 5)
      false

      iex> Settings.within_max_range?(40, :none)
      true
  """
  @spec within_max_range?(pos_integer(), pos_integer() | :none) :: boolean()
  def within_max_range?(_range, :none), do: true
  def within_max_range?(range, max_range), do: range <= max_range
end
