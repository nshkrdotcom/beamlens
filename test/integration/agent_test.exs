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

    test "populates events with snapshot first, then interleaved LLMCall and ToolCall" do
      {:ok, analysis} = Beamlens.Agent.run(max_iterations: 10)

      assert is_list(analysis.events)
      assert length(analysis.events) >= 2

      # First event should be the snapshot ToolCall (collected upfront)
      [snapshot_event | rest] = analysis.events
      assert %Beamlens.Events.ToolCall{intent: "snapshot"} = snapshot_event
      assert is_map(snapshot_event.result)
      assert Map.has_key?(snapshot_event.result, :overview)

      # Remaining events should be interleaved: LLMCall, ToolCall, LLMCall, ...
      # Verify we have both types of events
      llm_calls = Enum.filter(rest, &match?(%Beamlens.Events.LLMCall{}, &1))
      tool_calls = Enum.filter(rest, &match?(%Beamlens.Events.ToolCall{}, &1))

      assert llm_calls != []

      # Verify LLMCall events have expected structure
      [first_llm_call | _] = llm_calls
      assert is_binary(first_llm_call.tool_selected)
      assert %DateTime{} = first_llm_call.occurred_at
      assert is_integer(first_llm_call.iteration)

      # Verify any additional ToolCall events have expected structure
      Enum.each(tool_calls, fn tool_call ->
        assert is_binary(tool_call.intent)
        assert %DateTime{} = tool_call.occurred_at
        assert is_map(tool_call.result)
      end)
    end

    test "includes JudgeCall event when judge is enabled (default)" do
      {:ok, analysis} = Beamlens.Agent.run(max_iterations: 10)

      judge_calls = Enum.filter(analysis.events, &match?(%Beamlens.Events.JudgeCall{}, &1))

      assert judge_calls != [], "Expected at least one JudgeCall event"

      [judge_call | _] = judge_calls
      assert judge_call.verdict in [:accept, :retry]
      assert judge_call.confidence in [:high, :medium, :low]
      assert is_list(judge_call.issues)
      assert is_binary(judge_call.feedback)
      assert is_integer(judge_call.attempt)
      assert %DateTime{} = judge_call.occurred_at
    end

    test "excludes JudgeCall events when judge is disabled" do
      {:ok, analysis} = Beamlens.Agent.run(max_iterations: 10, judge: false)

      judge_calls = Enum.filter(analysis.events, &match?(%Beamlens.Events.JudgeCall{}, &1))

      assert judge_calls == [], "Expected no JudgeCall events when judge: false"
    end
  end
end
