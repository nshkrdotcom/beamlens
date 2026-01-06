defmodule Beamlens.Watchers.Watcher do
  @moduledoc """
  Behaviour for implementing domain-specific watchers (workers).

  Watchers are the worker agents in the **Orchestrator-Workers** pattern.
  They run continuously on their own cron schedule, monitor a specific domain
  (BEAM, Ecto, OS, etc.), and report anomalies UP to the orchestrator.

  ## How it Works

  Watchers use LLM-driven baseline learning to detect anomalies:

  1. Collect metrics via `collect_snapshot/1`
  2. Convert to observation via `snapshot_to_observation/1`
  3. Accumulate observations in a rolling window
  4. LLM analyzes patterns and decides: continue observing, report anomaly, or report healthy

  The orchestrator is the true **agent** with dynamic tool selection.

  ## Implementing a Watcher

      defmodule MyApp.Watchers.Postgres do
        @behaviour Beamlens.Watchers.Watcher

        @impl true
        def domain, do: :postgres

        @impl true
        def tools do
          [
            %Beamlens.Tool{
              name: :pool_stats,
              intent: "get_pool_stats",
              description: "Get connection pool statistics",
              execute: fn _params -> get_pool_stats() end
            }
          ]
        end

        @impl true
        def init(_config), do: {:ok, %{}}

        @impl true
        def collect_snapshot(_state) do
          %{pool_size: get_pool_size(), available: get_available(), waiting: get_waiting()}
        end

        @impl true
        def baseline_config, do: %{window_size: 60, min_observations: 5}

        @impl true
        def snapshot_to_observation(snapshot) do
          %PostgresObservation{
            observed_at: DateTime.utc_now(),
            pool_size: snapshot.pool_size,
            available: snapshot.available,
            waiting: snapshot.waiting
          }
        end

        @impl true
        def format_observations_for_prompt(observations) do
          Enum.map_join(observations, "\\n", &PostgresObservation.to_prompt_string/1)
        end

        @impl true
        def compute_baseline_statistics(observations) do
          %{waiting: %{mean: avg(observations, :waiting), std: std(observations, :waiting)}}
        end
      end

  ## Configuration

  Watchers are configured in the application config:

      config :beamlens,
        watchers: [
          {:beam, "*/1 * * * *"},
          [name: :postgres, watcher_module: MyApp.Watchers.Postgres, cron: "*/5 * * * *"]
        ]
  """

  alias Beamlens.Tool

  @type state :: term()
  @type snapshot :: map()
  @type observation :: term()

  @type baseline_config :: %{
          optional(:window_size) => pos_integer(),
          optional(:min_observations) => pos_integer()
        }

  @doc """
  Returns the domain this watcher monitors.

  The domain is used to identify the watcher in reports and telemetry.

  ## Examples

      def domain, do: :beam
      def domain, do: :ecto
      def domain, do: :os
  """
  @callback domain() :: atom()

  @doc """
  Returns list of tools this watcher provides to the orchestrator.

  These tools become available to the orchestrator for deeper investigation
  when it receives reports from this watcher.
  """
  @callback tools() :: [Tool.t()]

  @doc """
  Initializes watcher state from configuration.

  Called once when the watcher server starts. The config comes from the
  `:config` key in the watcher configuration.

  ## Example

      def init(_config), do: {:ok, %{}}
  """
  @callback init(config :: keyword()) :: {:ok, state()} | {:error, term()}

  @doc """
  Collects current metrics snapshot from the domain.

  This should be fast and read-only. The returned map will be included
  in reports as frozen evidence.

  ## Example

      def collect_snapshot(_state) do
        %{
          memory_utilization_pct: calculate_memory_pct(),
          process_count: :erlang.system_info(:process_count)
        }
      end
  """
  @callback collect_snapshot(state()) :: snapshot()

  @doc """
  Returns baseline detection configuration.

  ## Options

    * `:window_size` - Number of observations to retain (default: 60)
    * `:min_observations` - Minimum observations before analyzing (default: 3)

  ## Example

      def baseline_config do
        %{window_size: 60, min_observations: 5}
      end
  """
  @callback baseline_config() :: baseline_config()

  @doc """
  Converts a snapshot to a domain-specific observation struct.

  Observations are compact representations of snapshots optimized
  for baseline analysis. They should contain the key metrics that
  matter for anomaly detection.

  ## Example

      def snapshot_to_observation(snapshot) do
        BeamObservation.new(snapshot)
      end
  """
  @callback snapshot_to_observation(snapshot()) :: observation()

  @doc """
  Formats a list of observations as text for the LLM prompt.

  The output should be human-readable and include timestamps
  and key metric values. The LLM will analyze these observations
  directly to establish baselines and detect anomalies.

  ## Example

      def format_observations_for_prompt(observations) do
        BeamObservation.format_list(observations)
      end
  """
  @callback format_observations_for_prompt([observation()]) :: String.t()
end
