defmodule Beamlens.Events.LLMCall do
  @moduledoc """
  Captures an LLM decision point in the agent loop.

  This event is recorded each time the LLM responds with a tool selection,
  showing the agent's decision-making process.

  ## Fields

    * `:occurred_at` - When the LLM response was received
    * `:iteration` - The iteration number in the agent loop (0-indexed)
    * `:tool_selected` - The intent of the tool the LLM chose to execute
      (or "done" when completing the analysis)
  """

  @type t :: %__MODULE__{
          occurred_at: DateTime.t(),
          iteration: non_neg_integer(),
          tool_selected: String.t()
        }

  @derive Jason.Encoder
  @enforce_keys [:occurred_at, :iteration, :tool_selected]
  defstruct [:occurred_at, :iteration, :tool_selected]
end
