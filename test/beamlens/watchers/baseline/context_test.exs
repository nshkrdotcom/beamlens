defmodule Beamlens.Watchers.Baseline.ContextTest do
  @moduledoc false

  use ExUnit.Case

  alias Beamlens.Watchers.Baseline.Context

  describe "new/0" do
    test "creates empty context" do
      ctx = Context.new()

      assert ctx.first_observation_at == nil
      assert ctx.observation_count == 0
      assert ctx.llm_notes == nil
    end
  end

  describe "record_observation/1" do
    test "increments observation count" do
      ctx =
        Context.new()
        |> Context.record_observation()
        |> Context.record_observation()

      assert ctx.observation_count == 2
    end

    test "sets first_observation_at on first observation" do
      ctx =
        Context.new()
        |> Context.record_observation()

      assert %DateTime{} = ctx.first_observation_at
    end

    test "preserves first_observation_at on subsequent observations" do
      ctx = Context.new() |> Context.record_observation()
      first_at = ctx.first_observation_at

      ctx = Context.record_observation(ctx)

      assert ctx.first_observation_at == first_at
    end
  end

  describe "update_notes/2" do
    test "stores LLM notes" do
      ctx =
        Context.new()
        |> Context.update_notes("Memory stable around 45%")

      assert ctx.llm_notes == "Memory stable around 45%"
    end

    test "handles nil notes" do
      ctx =
        Context.new()
        |> Context.update_notes("Initial notes")
        |> Context.update_notes(nil)

      assert ctx.llm_notes == "Initial notes"
    end
  end

  describe "hours_observed/1" do
    test "returns 0.0 for new context" do
      assert Context.hours_observed(Context.new()) == 0.0
    end

    test "returns positive value after observations" do
      ctx =
        Context.new()
        |> Context.record_observation()

      hours = Context.hours_observed(ctx)
      assert is_float(hours)
      assert hours >= 0.0
    end
  end

  describe "reset/1" do
    test "returns fresh context" do
      ctx =
        Context.new()
        |> Context.record_observation()
        |> Context.record_observation()
        |> Context.update_notes("Some notes")
        |> Context.reset()

      assert ctx.first_observation_at == nil
      assert ctx.observation_count == 0
      assert ctx.llm_notes == nil
    end
  end
end
