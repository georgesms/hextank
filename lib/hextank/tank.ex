defmodule Hextank.Tank do
  @moduledoc """
  One player's tank. A tank with 0 HP is a **ghost**: it has left the board
  (`position: nil`) and gets one vote per tick to give 1 AP to a living tank.
  """

  alias Hextank.Hex

  @enforce_keys [:player_id, :name, :seat]
  defstruct [
    :player_id,
    :name,
    # Join order, from 1. Gives each tank its colour.
    :seat,
    position: nil,
    hp: 3,
    ap: 0,
    range: 2,
    # Ghosts only: whether this tick's vote is still available.
    has_vote: false,
    # A banned player's tank stays on the board but never acts again (Phase 5).
    frozen: false,
    # Which way the hull points: the index (0..5) of the direction of the last cell
    # it drove to (see Hextank.Hex.directions/0).
    heading: 0,
    # Which way the turret points: the last target's position minus the tank's, at
    # the time of the shot (a hex used as an offset). nil: along the hull.
    aim: nil
  ]

  @type t :: %__MODULE__{
          player_id: String.t(),
          name: String.t(),
          seat: pos_integer(),
          position: Hex.t() | nil,
          hp: non_neg_integer(),
          ap: non_neg_integer(),
          range: pos_integer(),
          has_vote: boolean(),
          frozen: boolean(),
          heading: 0..5,
          aim: Hex.t() | nil
        }

  @doc "Whether the tank is still on the board."
  @spec alive?(t()) :: boolean()
  def alive?(tank), do: tank.hp > 0

  @doc "Whether the tank is a ghost."
  @spec ghost?(t()) :: boolean()
  def ghost?(tank), do: tank.hp == 0
end
