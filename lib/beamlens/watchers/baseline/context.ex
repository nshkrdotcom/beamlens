defmodule Beamlens.Watchers.Baseline.Context do
  @moduledoc """
  Stores LLM notes and metadata for baseline learning.

  This context persists across observations, allowing the LLM to
  maintain notes about learned patterns and baseline characteristics.
  """

  defstruct [
    :first_observation_at,
    observation_count: 0,
    llm_notes: nil
  ]

  @type t :: %__MODULE__{
          first_observation_at: DateTime.t() | nil,
          observation_count: non_neg_integer(),
          llm_notes: String.t() | nil
        }

  @doc """
  Creates a new empty baseline context.
  """
  def new do
    %__MODULE__{}
  end

  @doc """
  Records a new observation in the context.

  Updates the observation count and sets the first observation timestamp
  if this is the first observation.
  """
  def record_observation(%__MODULE__{} = ctx) do
    first_at = ctx.first_observation_at || DateTime.utc_now()

    %{ctx | observation_count: ctx.observation_count + 1, first_observation_at: first_at}
  end

  @doc """
  Updates the LLM notes.

  Called when the LLM returns notes to remember for the next analysis.
  """
  def update_notes(%__MODULE__{} = ctx, notes) when is_binary(notes) do
    %{ctx | llm_notes: notes}
  end

  def update_notes(%__MODULE__{} = ctx, nil), do: ctx

  @doc """
  Returns the duration of observation in hours.

  Returns 0.0 if no observations have been recorded yet.
  """
  def hours_observed(%__MODULE__{first_observation_at: nil}), do: 0.0

  def hours_observed(%__MODULE__{first_observation_at: first_at}) do
    diff_seconds = DateTime.diff(DateTime.utc_now(), first_at, :second)
    Float.round(diff_seconds / 3600, 2)
  end

  @doc """
  Resets the context to initial state.

  Used after reporting an anomaly to start fresh observation period.
  """
  def reset(%__MODULE__{}) do
    new()
  end
end
