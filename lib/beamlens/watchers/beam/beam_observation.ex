defmodule Beamlens.Watchers.Beam.BeamObservation do
  @moduledoc """
  BEAM-specific observation struct for baseline learning.

  Captures key VM metrics from a snapshot for trend analysis.
  Each observation is a point-in-time view of the VM state.
  """

  @enforce_keys [:observed_at]
  defstruct [
    :observed_at,
    :memory_pct,
    :process_pct,
    :port_pct,
    :atom_pct,
    :run_queue,
    :schedulers_online
  ]

  @type t :: %__MODULE__{
          observed_at: DateTime.t(),
          memory_pct: float() | nil,
          process_pct: float() | nil,
          port_pct: float() | nil,
          atom_pct: float() | nil,
          run_queue: non_neg_integer() | nil,
          schedulers_online: pos_integer() | nil
        }

  @doc """
  Creates a new observation from a BEAM snapshot.

  Extracts key metrics from the snapshot's overview section.
  """
  def new(snapshot) when is_map(snapshot) do
    overview = Map.get(snapshot, :overview, %{})

    %__MODULE__{
      observed_at: DateTime.utc_now(),
      memory_pct: Map.get(overview, :memory_utilization_pct),
      process_pct: Map.get(overview, :process_utilization_pct),
      port_pct: Map.get(overview, :port_utilization_pct),
      atom_pct: Map.get(overview, :atom_utilization_pct),
      run_queue: Map.get(overview, :scheduler_run_queue),
      schedulers_online: Map.get(overview, :schedulers_online)
    }
  end

  @doc """
  Formats the observation as a string for LLM prompts.

  Returns a concise, parseable representation of the observation.
  """
  def to_prompt_string(%__MODULE__{} = obs) do
    timestamp = DateTime.to_iso8601(obs.observed_at)

    "#{timestamp}: mem=#{obs.memory_pct}%, proc=#{obs.process_pct}%, " <>
      "port=#{obs.port_pct}%, atom=#{obs.atom_pct}%, " <>
      "rq=#{obs.run_queue}, sched=#{obs.schedulers_online}"
  end

  @doc """
  Formats a list of observations for LLM prompts.

  Returns observations newest-first with one per line.
  """
  def format_list(observations) when is_list(observations) do
    Enum.map_join(observations, "\n", &to_prompt_string/1)
  end
end
