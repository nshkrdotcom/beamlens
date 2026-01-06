defmodule Beamlens.Watchers.ObservationHistoryTest do
  @moduledoc false

  use ExUnit.Case

  alias Beamlens.Watchers.ObservationHistory

  describe "new/1" do
    test "creates empty history with default window size" do
      history = ObservationHistory.new()

      assert history.window_size == 60
      assert history.observations == []
      assert history.total_count == 0
    end

    test "creates empty history with custom window size" do
      history = ObservationHistory.new(window_size: 10)

      assert history.window_size == 10
    end
  end

  describe "add/2" do
    test "adds observation to empty history" do
      history = ObservationHistory.new()
      history = ObservationHistory.add(history, :obs1)

      assert history.observations == [:obs1]
      assert history.total_count == 1
    end

    test "prepends new observations (newest first)" do
      history =
        ObservationHistory.new()
        |> ObservationHistory.add(:obs1)
        |> ObservationHistory.add(:obs2)
        |> ObservationHistory.add(:obs3)

      assert history.observations == [:obs3, :obs2, :obs1]
      assert history.total_count == 3
    end

    test "respects window size limit" do
      history =
        ObservationHistory.new(window_size: 3)
        |> ObservationHistory.add(:obs1)
        |> ObservationHistory.add(:obs2)
        |> ObservationHistory.add(:obs3)
        |> ObservationHistory.add(:obs4)

      assert history.observations == [:obs4, :obs3, :obs2]
      assert history.total_count == 4
    end
  end

  describe "count/1" do
    test "returns 0 for empty history" do
      assert ObservationHistory.count(ObservationHistory.new()) == 0
    end

    test "returns number of stored observations" do
      history =
        ObservationHistory.new()
        |> ObservationHistory.add(:a)
        |> ObservationHistory.add(:b)

      assert ObservationHistory.count(history) == 2
    end
  end

  describe "empty?/1" do
    test "returns true for empty history" do
      assert ObservationHistory.empty?(ObservationHistory.new())
    end

    test "returns false for non-empty history" do
      history = ObservationHistory.add(ObservationHistory.new(), :obs)
      refute ObservationHistory.empty?(history)
    end
  end

  describe "latest/1" do
    test "returns nil for empty history" do
      assert ObservationHistory.latest(ObservationHistory.new()) == nil
    end

    test "returns most recent observation" do
      history =
        ObservationHistory.new()
        |> ObservationHistory.add(:first)
        |> ObservationHistory.add(:second)

      assert ObservationHistory.latest(history) == :second
    end
  end

  describe "oldest/1" do
    test "returns nil for empty history" do
      assert ObservationHistory.oldest(ObservationHistory.new()) == nil
    end

    test "returns oldest observation in window" do
      history =
        ObservationHistory.new()
        |> ObservationHistory.add(:first)
        |> ObservationHistory.add(:second)

      assert ObservationHistory.oldest(history) == :first
    end
  end

  describe "to_list/1" do
    test "returns observations newest first" do
      history =
        ObservationHistory.new()
        |> ObservationHistory.add(:a)
        |> ObservationHistory.add(:b)
        |> ObservationHistory.add(:c)

      assert ObservationHistory.to_list(history) == [:c, :b, :a]
    end
  end

  describe "to_list_oldest_first/1" do
    test "returns observations oldest first" do
      history =
        ObservationHistory.new()
        |> ObservationHistory.add(:a)
        |> ObservationHistory.add(:b)
        |> ObservationHistory.add(:c)

      assert ObservationHistory.to_list_oldest_first(history) == [:a, :b, :c]
    end
  end

  describe "take/2" do
    test "returns most recent n observations" do
      history =
        ObservationHistory.new()
        |> ObservationHistory.add(:a)
        |> ObservationHistory.add(:b)
        |> ObservationHistory.add(:c)

      assert ObservationHistory.take(history, 2) == [:c, :b]
    end
  end
end
