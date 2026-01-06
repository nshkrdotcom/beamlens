defmodule Beamlens.Watchers.Baseline.Analyzer do
  @moduledoc """
  LLM-based baseline analysis using Puck.

  Analyzes observation history and context to decide whether to:
  - Continue observing (need more data)
  - Report an anomaly (deviation detected)
  - Report healthy (baseline established, all normal)
  """

  alias Beamlens.Watchers.Baseline.{Context, Decision}
  alias Beamlens.Watchers.ObservationHistory

  @default_timeout :timer.seconds(30)

  @doc """
  Analyzes observations and returns a baseline decision.

  ## Options

    * `:llm_client` - LLM client name to use
    * `:client_registry` - Client registry for dynamic client selection
    * `:timeout` - Timeout for LLM call (default: 30s)
    * `:trace_id` - Correlation ID for telemetry
  """
  def analyze(domain, history, context, watcher_module, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    trace_id = Keyword.get(opts, :trace_id)

    observations = ObservationHistory.to_list(history)
    observations_text = watcher_module.format_observations_for_prompt(observations)

    prompt = build_prompt(domain, observations_text, history.total_count, context)

    backend_config =
      %{
        function: "AnalyzeBaseline",
        args_format: :messages,
        path: Application.app_dir(:beamlens, "priv/baml_src")
      }
      |> maybe_add_client_config(opts)

    client =
      Puck.Client.new(
        {Puck.Backends.Baml, backend_config},
        hooks: Beamlens.Telemetry.Hooks
      )

    puck_context =
      Puck.Context.new(messages: [Puck.Message.new(:user, prompt)])

    task =
      Task.async(fn ->
        Puck.call(client, [], puck_context, output_schema: Decision.schema())
      end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, response, _context}} ->
        emit_telemetry(:decision, %{
          trace_id: trace_id,
          domain: domain,
          intent: response.content.intent
        })

        {:ok, response.content}

      {:ok, {:error, reason}} ->
        emit_telemetry(:error, %{
          trace_id: trace_id,
          domain: domain,
          reason: reason
        })

        {:error, reason}

      nil ->
        emit_telemetry(:timeout, %{
          trace_id: trace_id,
          domain: domain
        })

        {:error, :timeout}
    end
  end

  defp build_prompt(domain, observations_text, observation_count, context) do
    hours = Context.hours_observed(context)
    notes = context.llm_notes

    """
    Domain: #{domain}
    Observations (#{observation_count} total, #{Float.round(hours, 2)} hours):

    #{observations_text}

    #{if notes, do: "Previous notes: #{notes}", else: ""}
    """
  end

  defp maybe_add_client_config(config, opts) do
    llm_client = Keyword.get(opts, :llm_client)
    client_registry = Keyword.get(opts, :client_registry)

    cond do
      is_map(client_registry) -> Map.put(config, :client_registry, client_registry)
      llm_client != nil -> Map.put(config, :llm_client, llm_client)
      true -> config
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:beamlens, :baseline, :analyzer, event],
      %{system_time: System.system_time()},
      metadata
    )
  end
end
