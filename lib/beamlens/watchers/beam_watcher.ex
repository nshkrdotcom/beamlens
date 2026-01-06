defmodule Beamlens.Watchers.BeamWatcher do
  @moduledoc """
  Watcher for BEAM VM metrics.

  Uses LLM-driven baseline learning to detect anomalies based on
  learned patterns specific to the application. The LLM observes
  metrics over time and decides what "normal" looks like.

  ## How it Works

  1. On each cron tick, collects a snapshot of BEAM metrics
  2. Converts snapshot to a compact observation (memory%, process%, etc.)
  3. Adds observation to a rolling window (default 60 observations)
  4. After minimum observations (default 3), calls LLM to analyze
  5. LLM decides: continue observing, report anomaly, or report healthy

  ## Configuration

      # Default: baseline mode with 60-observation window
      {:beam, "*/1 * * * *"}
  """

  @behaviour Beamlens.Watchers.Watcher

  alias Beamlens.Collectors.Beam
  alias Beamlens.Watchers.Beam.BeamObservation

  @impl true
  def domain, do: :beam

  @impl true
  def tools do
    Beam.tools()
  end

  @impl true
  def init(_config) do
    {:ok, %{}}
  end

  @impl true
  def baseline_config do
    %{window_size: 60, min_observations: 3}
  end

  @impl true
  def snapshot_to_observation(snapshot) do
    BeamObservation.new(snapshot)
  end

  @impl true
  def format_observations_for_prompt(observations) do
    BeamObservation.format_list(observations)
  end

  @impl true
  def collect_snapshot(_state) do
    Beam.snapshot()
  end
end
