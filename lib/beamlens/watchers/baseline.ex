defmodule Beamlens.Watchers.Baseline do
  @moduledoc """
  Baseline learning and anomaly detection for watchers.

  This module provides the LLM-based baseline analysis that allows watchers
  to learn normal system behavior and detect anomalies without manual threshold
  configuration.

  ## Components

    * `Beamlens.Watchers.Baseline.Analyzer` - LLM-based analysis engine
    * `Beamlens.Watchers.Baseline.Context` - Observation metadata and LLM notes
    * `Beamlens.Watchers.Baseline.Decision` - Decision structs (continue, report, healthy)
  """
end
