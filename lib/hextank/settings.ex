defmodule Hextank.Settings do
  @moduledoc """
  The settings a table's creator can choose (besides the tick interval, which lives on
  `%Game{}` itself): board size, how many rocks, and each tank's starting HP and
  range. Chosen when the table is created, fixed afterwards.
  """

  @defaults %{board_radius: :auto, obstacle_percent: 10, start_hp: 3, start_range: 2}

  @allowed %{
    # :auto grows the board with the number of players (see Board.radius_for/1).
    board_radius: [:auto | Enum.to_list(3..12)],
    obstacle_percent: [0, 5, 10, 20],
    start_hp: Enum.to_list(1..5),
    start_range: Enum.to_list(1..4)
  }

  @type t :: %{
          board_radius: :auto | pos_integer(),
          obstacle_percent: non_neg_integer(),
          start_hp: pos_integer(),
          start_range: pos_integer()
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
  Fills in the defaults for anything missing, and checks every value is allowed.

      iex> Settings.validate(%{start_hp: 5})
      {:ok, %{board_radius: :auto, obstacle_percent: 10, start_hp: 5, start_range: 2}}

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
end
