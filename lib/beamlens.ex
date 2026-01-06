defmodule Beamlens do
  @moduledoc """
  BeamLens - AI-powered BEAM VM health monitoring.

  An orchestrator-workers architecture where specialized **watchers** monitor
  BEAM VM metrics on cron schedules and report anomalies to an **orchestrator**
  that correlates findings and conducts deeper investigations using AI.

  ## Architecture

  ```
  ┌─────────────────┐     ┌─────────────────┐
  │  BEAM Watcher   │     │  Custom Watcher │
  │    (worker)     │     │    (worker)     │
  └────────┬────────┘     └────────┬────────┘
           │ report (only if anomaly)       │
           └───────────────┬───────────────┘
                           ▼
              ┌────────────────────────┐
              │    ReportHandler       │
              │   - receives reports   │
              │   - triggers Agent     │
              │   - correlates & AI    │
              └────────────────────────┘
  ```

  ## Installation

  Add to your dependencies:

      {:beamlens, github: "bradleygolden/beamlens"}

  ## Supervision Tree Setup

  Add BeamLens to your application's supervision tree:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            {Beamlens, watchers: [{:beam, "*/5 * * * *"}]}
          ]

          Supervisor.start_link(children, strategy: :one_for_one)
        end
      end

  ## Configuration Options

  Options passed to `Beamlens`:

    * `:watchers` - List of watcher configurations (see below)
    * `:report_handler` - Report handler options:
      * `:trigger` - `:on_report` (auto-run) or `:manual` (default: `:on_report`)
    * `:circuit_breaker` - Circuit breaker options (see below)

  ### Watcher Configuration

  Watchers can be specified using tuple shorthand or full keyword lists:

      # Built-in BEAM watcher
      {:beam, "*/5 * * * *"}

      # Custom watcher
      [name: :postgres, watcher_module: MyApp.Watchers.Postgres,
       cron: "*/10 * * * *", config: [repo: MyApp.Repo]]

  ### Example Configuration

      {Beamlens,
        watchers: [
          {:beam, "*/1 * * * *"},
          [name: :postgres, watcher_module: MyApp.Watchers.Postgres,
           cron: "*/5 * * * *", config: [repo: MyApp.Repo]]
        ],
        report_handler: [
          trigger: :on_report
        ],
        circuit_breaker: [
          enabled: true
        ]}

  ## Manual Usage

  You can run analyses manually:

      # Run the original agent directly (snapshot + tool loop)
      {:ok, analysis} = Beamlens.run()

      # Investigate pending watcher reports
      {:ok, analysis} = Beamlens.investigate()

      # Trigger a specific watcher manually
      :ok = Beamlens.trigger_watcher(:beam)

  ## Runtime API

      # List all running watchers
      Beamlens.list_watchers()

      # Check for pending reports
      Beamlens.pending_reports?()

      # Trigger specific watcher
      Beamlens.trigger_watcher(:beam)

  ## Telemetry Events

  BeamLens emits telemetry events for observability. See `Beamlens.Telemetry`
  for the full list of events.
  """

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(opts) do
    Beamlens.Supervisor.start_link(opts)
  end

  @doc """
  Manually trigger a health analysis using the direct agent loop.

  This bypasses watchers and runs a complete analysis immediately,
  collecting a snapshot and using the AI to investigate.

  Returns `{:ok, analysis}` on success, or `{:error, reason}` on failure.

  ## Options

  See `Beamlens.Agent.run/1` for available options.

  ## Possible Errors

    * `{:error, :max_iterations_exceeded}` - Agent did not complete within iteration limit
    * `{:error, :timeout}` - LLM call timed out
    * `{:error, :circuit_open}` - Circuit breaker is open due to consecutive failures
    * `{:error, {:unknown_tool, tool}}` - LLM returned unrecognized tool
    * `{:error, {:encoding_failed, tool_name, reason}}` - Tool result could not be JSON-encoded
  """
  defdelegate run(opts \\ []), to: Beamlens.Agent

  @doc """
  Investigates pending watcher reports using the agent's tool-calling loop.

  Takes all reports from the queue and runs an investigation to correlate
  findings and analyze deeper.

  Returns `{:ok, analysis}` if reports were processed,
  `{:ok, :no_reports}` if no reports were pending.

  ## Options

    * `:trace_id` - Correlation ID for telemetry (auto-generated if not provided)
  """
  def investigate(opts \\ []) do
    Beamlens.ReportHandler.investigate(Beamlens.ReportHandler, opts)
  end

  @doc """
  Lists all running watchers with their status.

  Returns a list of maps with watcher information including:
    * `:name` - Watcher name
    * `:watcher` - Domain being monitored
    * `:cron` - Cron schedule
    * `:next_run_at` - Next scheduled run
    * `:last_run_at` - Last run time
    * `:run_count` - Number of times the watcher has run
  """
  defdelegate list_watchers(), to: Beamlens.Watchers.Supervisor

  @doc """
  Triggers an immediate check for a specific watcher.

  Useful for testing or manual intervention.

  Returns `:ok` on success, `{:error, :not_found}` if watcher doesn't exist.
  """
  defdelegate trigger_watcher(name), to: Beamlens.Watchers.Supervisor

  @doc """
  Gets the status of a specific watcher.

  Returns `{:ok, status}` on success, `{:error, :not_found}` if watcher doesn't exist.
  """
  defdelegate watcher_status(name), to: Beamlens.Watchers.Supervisor

  @doc """
  Checks if there are pending reports to investigate.
  """
  defdelegate pending_reports?(), to: Beamlens.ReportQueue, as: :pending?

  @doc """
  Returns the current circuit breaker state.

  ## Example

      Beamlens.circuit_breaker_state()
      #=> %{
      #=>   state: :closed,
      #=>   failure_count: 0,
      #=>   success_count: 0,
      #=>   failure_threshold: 5,
      #=>   reset_timeout: 30000,
      #=>   success_threshold: 2,
      #=>   last_failure_at: nil,
      #=>   last_failure_reason: nil
      #=> }
  """
  defdelegate circuit_breaker_state(), to: Beamlens.CircuitBreaker, as: :get_state

  @doc """
  Resets the circuit breaker to closed state.

  Use with caution - primarily for manual recovery after resolving issues.
  """
  defdelegate reset_circuit_breaker(), to: Beamlens.CircuitBreaker, as: :reset
end
