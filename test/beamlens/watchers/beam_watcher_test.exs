defmodule Beamlens.Watchers.BeamWatcherTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Beamlens.Watchers.Beam.BeamObservation
  alias Beamlens.Watchers.BeamWatcher

  describe "domain/0" do
    test "returns :beam" do
      assert BeamWatcher.domain() == :beam
    end
  end

  describe "tools/0" do
    test "returns list of tools" do
      tools = BeamWatcher.tools()

      assert is_list(tools)
      assert tools != []
      assert Enum.all?(tools, &match?(%Beamlens.Tool{}, &1))
    end

    test "includes overview tool" do
      tools = BeamWatcher.tools()
      tool_names = Enum.map(tools, & &1.name)

      assert :overview in tool_names
    end
  end

  describe "init/1" do
    test "initializes with empty state" do
      {:ok, state} = BeamWatcher.init([])

      assert state == %{}
    end
  end

  describe "collect_snapshot/1" do
    test "returns snapshot with expected keys" do
      {:ok, state} = BeamWatcher.init([])
      snapshot = BeamWatcher.collect_snapshot(state)

      assert Map.has_key?(snapshot, :overview)
      assert Map.has_key?(snapshot, :system_info)
      assert Map.has_key?(snapshot, :memory_stats)
      assert Map.has_key?(snapshot, :process_stats)
    end

    test "overview contains utilization percentages" do
      {:ok, state} = BeamWatcher.init([])
      snapshot = BeamWatcher.collect_snapshot(state)

      assert Map.has_key?(snapshot.overview, :memory_utilization_pct)
      assert Map.has_key?(snapshot.overview, :process_utilization_pct)
      assert Map.has_key?(snapshot.overview, :port_utilization_pct)
      assert Map.has_key?(snapshot.overview, :atom_utilization_pct)
      assert Map.has_key?(snapshot.overview, :scheduler_run_queue)
    end
  end

  describe "baseline_config/0" do
    test "returns window_size and min_observations" do
      config = BeamWatcher.baseline_config()

      assert config.window_size == 60
      assert config.min_observations == 3
    end
  end

  describe "snapshot_to_observation/1" do
    test "converts snapshot to BeamObservation" do
      {:ok, state} = BeamWatcher.init([])
      snapshot = BeamWatcher.collect_snapshot(state)
      observation = BeamWatcher.snapshot_to_observation(snapshot)

      assert %BeamObservation{} = observation
      assert observation.observed_at != nil
      assert is_number(observation.memory_pct)
      assert is_number(observation.process_pct)
    end
  end

  describe "format_observations_for_prompt/1" do
    test "formats observations as newline-separated strings" do
      {:ok, state} = BeamWatcher.init([])
      snapshot = BeamWatcher.collect_snapshot(state)
      observation = BeamWatcher.snapshot_to_observation(snapshot)

      result = BeamWatcher.format_observations_for_prompt([observation, observation])

      assert is_binary(result)
      assert result =~ "mem="
      assert result =~ "proc="
      lines = String.split(result, "\n")
      assert length(lines) == 2
    end
  end
end
