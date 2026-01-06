defmodule Beamlens.ReportQueue do
  @moduledoc """
  In-memory queue for reports from watchers to the orchestrator.

  Provides the unidirectional communication channel in the **Orchestrator-Workers**
  pattern. Watchers push reports when they detect anomalies, and the orchestrator
  takes reports for investigation.

  ## Features

    * FIFO queue ordering
    * Subscriber notifications when reports arrive
    * Atomic take-all operation for batch processing

  ## Example

      # Watcher pushes a report
      Beamlens.ReportQueue.push(report)

      # Orchestrator takes all pending reports
      reports = Beamlens.ReportQueue.take_all()

      # Subscribe to report notifications
      Beamlens.ReportQueue.subscribe()
      receive do
        {:report_available, report} -> handle_report(report)
      end
  """

  use GenServer

  alias Beamlens.Report

  defstruct reports: :queue.new(), subscribers: MapSet.new()

  @doc """
  Starts the ReportQueue GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Pushes a report onto the queue.

  Notifies all subscribers that a report is available.
  """
  def push(%Report{} = report, server \\ __MODULE__) do
    GenServer.cast(server, {:push, report})
  end

  @doc """
  Takes all pending reports from the queue.

  Returns a list of reports in FIFO order and clears the queue.
  Returns an empty list if no reports are pending.
  """
  def take_all(server \\ __MODULE__) do
    GenServer.call(server, :take_all)
  end

  @doc """
  Checks if there are pending reports in the queue.
  """
  def pending?(server \\ __MODULE__) do
    GenServer.call(server, :pending?)
  end

  @doc """
  Returns the number of pending reports.
  """
  def count(server \\ __MODULE__) do
    GenServer.call(server, :count)
  end

  @doc """
  Subscribes the calling process to report notifications.

  When a report is pushed, subscribers receive `{:report_available, report}`.
  Subscription is automatically removed when the subscriber process terminates.
  """
  def subscribe(server \\ __MODULE__) do
    GenServer.call(server, {:subscribe, self()})
  end

  @doc """
  Unsubscribes the calling process from report notifications.
  """
  def unsubscribe(server \\ __MODULE__) do
    GenServer.call(server, {:unsubscribe, self()})
  end

  @impl true
  def init(_opts) do
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:push, %Report{} = report}, state) do
    new_queue = :queue.in(report, state.reports)
    notify_subscribers(state.subscribers, report)
    {:noreply, %{state | reports: new_queue}}
  end

  @impl true
  def handle_call(:take_all, _from, state) do
    reports = :queue.to_list(state.reports)
    {:reply, reports, %{state | reports: :queue.new()}}
  end

  def handle_call(:pending?, _from, state) do
    {:reply, not :queue.is_empty(state.reports), state}
  end

  def handle_call(:count, _from, state) do
    {:reply, :queue.len(state.reports), state}
  end

  def handle_call({:subscribe, pid}, _from, state) do
    Process.monitor(pid)
    {:reply, :ok, %{state | subscribers: MapSet.put(state.subscribers, pid)}}
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    {:reply, :ok, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: MapSet.delete(state.subscribers, pid)}}
  end

  defp notify_subscribers(subscribers, report) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:report_available, report})
    end)
  end
end
