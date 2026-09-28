defmodule Hextank.Random do
  @moduledoc """
  Randomness that can be repeated: the same seed always gives the same result.

  The game core never calls `:rand` on its own. Callers pass a seed (an integer), so
  tests can use a fixed seed and real games a random one.
  """

  @doc """
  Shuffles a list. The same seed always gives the same order.

      iex> Random.shuffle([1, 2, 3, 4, 5], 42) == Random.shuffle([1, 2, 3, 4, 5], 42)
      true

      iex> Enum.sort(Random.shuffle([3, 1, 2], 7))
      [1, 2, 3]
  """
  @spec shuffle(list(), integer()) :: list()
  def shuffle(list, seed) do
    state = :rand.seed_s(:exsss, seed)

    # Give every item a random number, then sort by it. `map_reduce` carries the
    # random generator's state from one item to the next.
    {numbered, _state} =
      Enum.map_reduce(list, state, fn item, state ->
        {number, state} = :rand.uniform_s(state)
        {{number, item}, state}
      end)

    numbered
    |> Enum.sort_by(fn {number, _item} -> number end)
    |> Enum.map(fn {_number, item} -> item end)
  end
end
