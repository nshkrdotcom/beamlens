defmodule Beamlens.Events do
  @moduledoc """
  Event types for agent execution trace.

  Events capture everything that happens during an agent run - LLM decisions,
  tool executions, and future event types. They provide data provenance so users
  can verify AI conclusions against raw data.

  ## Event Types

    * `Beamlens.Events.LLMCall` - Captures an LLM decision (which tool was selected)
    * `Beamlens.Events.ToolCall` - Captures a tool execution with its result

  ## Example

      events = [
        %Events.LLMCall{occurred_at: ~U[...], iteration: 0, tool_selected: "get_system_info"},
        %Events.ToolCall{intent: "get_system_info", occurred_at: ~U[...], result: %{...}},
        %Events.LLMCall{occurred_at: ~U[...], iteration: 1, tool_selected: "done"}
      ]
  """

  alias Beamlens.Events.{LLMCall, ToolCall}

  @type t :: LLMCall.t() | ToolCall.t()
end
