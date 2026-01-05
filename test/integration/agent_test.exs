defmodule Beamlens.Integration.AgentTest do
  @moduledoc false

  use ExUnit.Case, async: false

  @moduletag :integration

  describe "Agent.run/1 with default provider" do
    @describetag timeout: 120_000

    test "runs agent loop and returns health analysis" do
      {:ok, analysis} = Beamlens.Agent.run(max_iterations: 10)

      assert %Beamlens.HealthAnalysis{} = analysis
      assert analysis.status in [:healthy, :warning, :critical]
      assert is_binary(analysis.summary)
      assert is_list(analysis.concerns)
      assert is_list(analysis.recommendations)
    end

    test "populates events with interleaved LLMCall and ToolCall" do
      {:ok, analysis} = Beamlens.Agent.run(max_iterations: 10)

      assert is_list(analysis.events)
      assert length(analysis.events) >= 2

      # Events should be interleaved: LLMCall, ToolCall, LLMCall, ToolCall, ...
      # First event should be an LLMCall (agent decides which tool to use)
      [first_event | _rest] = analysis.events
      assert %Beamlens.Events.LLMCall{} = first_event

      # Verify we have both types of events
      llm_calls = Enum.filter(analysis.events, &match?(%Beamlens.Events.LLMCall{}, &1))
      tool_calls = Enum.filter(analysis.events, &match?(%Beamlens.Events.ToolCall{}, &1))

      assert llm_calls != []
      assert tool_calls != []

      # Verify ToolCall events have results with expected structure
      [first_tool_call | _] = tool_calls
      assert is_binary(first_tool_call.intent)
      assert %DateTime{} = first_tool_call.occurred_at
      assert is_map(first_tool_call.result)

      # Verify LLMCall events have expected structure
      assert is_binary(first_event.tool_selected)
      assert %DateTime{} = first_event.occurred_at
      assert is_integer(first_event.iteration)
    end
  end
end
