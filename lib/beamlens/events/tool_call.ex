defmodule Beamlens.Events.ToolCall do
  @moduledoc """
  Captures a tool execution with its result.

  This event is recorded each time the agent executes a tool to collect
  metrics or data from the BEAM VM.

  ## Fields

    * `:intent` - The tool's intent string (e.g., "get_system_info", "get_memory_stats")
    * `:occurred_at` - When the tool execution completed
    * `:result` - The raw data returned by the tool
  """

  @type t :: %__MODULE__{
          intent: String.t(),
          occurred_at: DateTime.t(),
          result: map()
        }

  @derive Jason.Encoder
  @enforce_keys [:intent, :occurred_at, :result]
  defstruct [:intent, :occurred_at, :result]
end
