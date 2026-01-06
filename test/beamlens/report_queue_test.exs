defmodule Beamlens.ReportQueueTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Beamlens.{Report, ReportQueue}

  setup do
    {:ok, pid} = ReportQueue.start_link(name: nil)
    {:ok, queue: pid}
  end

  describe "push/2 and take_all/1" do
    test "returns empty list when queue is empty", %{queue: queue} do
      assert ReportQueue.take_all(queue) == []
    end

    test "returns single report after push", %{queue: queue} do
      report = make_report(:beam, :memory_elevated)
      ReportQueue.push(report, queue)

      reports = ReportQueue.take_all(queue)

      assert length(reports) == 1
      assert hd(reports).watcher == :beam
    end

    test "returns reports in FIFO order", %{queue: queue} do
      report1 = make_report(:beam, :memory_elevated)
      report2 = make_report(:ecto, :pool_exhausted)
      report3 = make_report(:os, :disk_full)

      ReportQueue.push(report1, queue)
      ReportQueue.push(report2, queue)
      ReportQueue.push(report3, queue)

      reports = ReportQueue.take_all(queue)

      assert length(reports) == 3
      assert Enum.map(reports, & &1.watcher) == [:beam, :ecto, :os]
    end

    test "clears queue after take_all", %{queue: queue} do
      ReportQueue.push(make_report(:beam, :memory_elevated), queue)

      assert length(ReportQueue.take_all(queue)) == 1
      assert ReportQueue.take_all(queue) == []
    end
  end

  describe "pending?/1" do
    test "returns false when queue is empty", %{queue: queue} do
      refute ReportQueue.pending?(queue)
    end

    test "returns true when queue has reports", %{queue: queue} do
      ReportQueue.push(make_report(:beam, :memory_elevated), queue)

      assert ReportQueue.pending?(queue)
    end

    test "returns false after take_all", %{queue: queue} do
      ReportQueue.push(make_report(:beam, :memory_elevated), queue)
      ReportQueue.take_all(queue)

      refute ReportQueue.pending?(queue)
    end
  end

  describe "count/1" do
    test "returns 0 when queue is empty", %{queue: queue} do
      assert ReportQueue.count(queue) == 0
    end

    test "returns correct count after pushes", %{queue: queue} do
      ReportQueue.push(make_report(:beam, :memory_elevated), queue)
      ReportQueue.push(make_report(:ecto, :pool_exhausted), queue)

      assert ReportQueue.count(queue) == 2
    end

    test "returns 0 after take_all", %{queue: queue} do
      ReportQueue.push(make_report(:beam, :memory_elevated), queue)
      ReportQueue.take_all(queue)

      assert ReportQueue.count(queue) == 0
    end
  end

  describe "subscribe/1 and notifications" do
    test "subscriber receives notification on push", %{queue: queue} do
      ReportQueue.subscribe(queue)
      report = make_report(:beam, :memory_elevated)

      ReportQueue.push(report, queue)

      assert_receive {:report_available, ^report}
    end

    test "multiple subscribers receive notifications", %{queue: queue} do
      parent = self()

      spawn(fn ->
        ReportQueue.subscribe(queue)
        send(parent, :subscribed)

        receive do
          {:report_available, report} -> send(parent, {:child_received, report})
        end
      end)

      receive do
        :subscribed -> :ok
      end

      ReportQueue.subscribe(queue)
      report = make_report(:beam, :memory_elevated)
      ReportQueue.push(report, queue)

      assert_receive {:report_available, ^report}
      assert_receive {:child_received, ^report}
    end

    test "unsubscribed process does not receive notifications", %{queue: queue} do
      ReportQueue.subscribe(queue)
      ReportQueue.unsubscribe(queue)

      ReportQueue.push(make_report(:beam, :memory_elevated), queue)

      refute_receive {:report_available, _}
    end

    test "dead subscriber is automatically removed", %{queue: queue} do
      parent = self()

      pid =
        spawn(fn ->
          ReportQueue.subscribe(queue)
          send(parent, :subscribed)

          receive do
            :exit -> :ok
          end
        end)

      receive do
        :subscribed -> :ok
      end

      send(pid, :exit)
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      end

      ReportQueue.push(make_report(:beam, :memory_elevated), queue)

      assert ReportQueue.count(queue) == 1
    end
  end

  defp make_report(watcher, anomaly_type) do
    Report.new(%{
      watcher: watcher,
      anomaly_type: anomaly_type,
      severity: :warning,
      summary: "Test report",
      snapshot: %{}
    })
  end
end
