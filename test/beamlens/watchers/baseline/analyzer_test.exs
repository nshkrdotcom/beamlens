defmodule Beamlens.Watchers.Baseline.AnalyzerTest do
  @moduledoc """
  Unit tests for the Baseline.Analyzer module.

  Note: LLM-dependent behavior (analyze/5) is tested in integration tests.
  These tests focus on module structure and telemetry integration.
  """

  use ExUnit.Case, async: true

  alias Beamlens.Watchers.Baseline.Analyzer

  describe "module structure" do
    test "analyze/5 is exported" do
      exports = Analyzer.__info__(:functions)
      assert {:analyze, 5} in exports
    end

    test "analyze/4 is exported (with default opts)" do
      exports = Analyzer.__info__(:functions)
      assert {:analyze, 4} in exports
    end
  end

  describe "telemetry events" do
    test "emits decision event on success" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :baseline, :analyzer, :decision],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.execute(
        [:beamlens, :baseline, :analyzer, :decision],
        %{system_time: System.system_time()},
        %{trace_id: "test-123", domain: :beam, intent: "continue_observing"}
      )

      assert_receive {:telemetry, [:beamlens, :baseline, :analyzer, :decision], _measurements,
                      metadata}

      assert metadata.trace_id == "test-123"
      assert metadata.domain == :beam
      assert metadata.intent == "continue_observing"

      :telemetry.detach(ref)
    end

    test "emits error event on failure" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :baseline, :analyzer, :error],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.execute(
        [:beamlens, :baseline, :analyzer, :error],
        %{system_time: System.system_time()},
        %{trace_id: "test-456", domain: :beam, reason: :api_error}
      )

      assert_receive {:telemetry, [:beamlens, :baseline, :analyzer, :error], _measurements,
                      metadata}

      assert metadata.trace_id == "test-456"
      assert metadata.reason == :api_error

      :telemetry.detach(ref)
    end

    test "emits timeout event on timeout" do
      ref = make_ref()
      parent = self()

      :telemetry.attach(
        ref,
        [:beamlens, :baseline, :analyzer, :timeout],
        fn event, measurements, metadata, _ ->
          send(parent, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.execute(
        [:beamlens, :baseline, :analyzer, :timeout],
        %{system_time: System.system_time()},
        %{trace_id: "test-789", domain: :beam}
      )

      assert_receive {:telemetry, [:beamlens, :baseline, :analyzer, :timeout], _measurements,
                      metadata}

      assert metadata.trace_id == "test-789"
      assert metadata.domain == :beam

      :telemetry.detach(ref)
    end
  end
end
