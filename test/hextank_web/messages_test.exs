defmodule HextankWeb.MessagesTest do
  use ExUnit.Case, async: true

  alias HextankWeb.Messages

  @day 86_400

  test "days left before deletion are rounded to the nearest day, at least 1" do
    assert Messages.deleted_in(7 * @day) == "Deleted in 7 days"
    # A page whose clock is a few seconds behind.
    assert Messages.deleted_in(7 * @day + 5) == "Deleted in 7 days"
    assert Messages.deleted_in(6 * @day + 13 * 3_600) == "Deleted in 7 days"
    assert Messages.deleted_in(6 * @day + 11 * 3_600) == "Deleted in 6 days"
    assert Messages.deleted_in(3_600) == "Deleted in 1 day"
  end

  test "a game's age is counted in whole days" do
    assert Messages.started_ago(3_600) == "Started less than a day ago"
    assert Messages.started_ago(@day) == "Started 1 day ago"
    assert Messages.started_ago(3 * @day + 3_600) == "Started 3 days ago"
  end
end
