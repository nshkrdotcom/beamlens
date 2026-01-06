defmodule Beamlens.Watchers.Beam.BeamObservationTest do
  @moduledoc false

  use ExUnit.Case

  alias Beamlens.Watchers.Beam.BeamObservation

  describe "new/1" do
    test "creates observation from snapshot with overview" do
      snapshot = %{
        overview: %{
          memory_utilization_pct: 45.5,
          process_utilization_pct: 12.3,
          port_utilization_pct: 0.5,
          atom_utilization_pct: 1.2,
          scheduler_run_queue: 0,
          schedulers_online: 8
        }
      }

      obs = BeamObservation.new(snapshot)

      assert %BeamObservation{} = obs
      assert obs.memory_pct == 45.5
      assert obs.process_pct == 12.3
      assert obs.port_pct == 0.5
      assert obs.atom_pct == 1.2
      assert obs.run_queue == 0
      assert obs.schedulers_online == 8
      assert %DateTime{} = obs.observed_at
    end

    test "handles missing overview gracefully" do
      obs = BeamObservation.new(%{})

      assert %BeamObservation{} = obs
      assert obs.memory_pct == nil
      assert obs.process_pct == nil
      assert %DateTime{} = obs.observed_at
    end

    test "handles partial overview" do
      snapshot = %{
        overview: %{
          memory_utilization_pct: 50.0
        }
      }

      obs = BeamObservation.new(snapshot)

      assert obs.memory_pct == 50.0
      assert obs.process_pct == nil
    end
  end

  describe "to_prompt_string/1" do
    test "formats observation as string" do
      obs = %BeamObservation{
        observed_at: ~U[2024-01-06 10:30:00Z],
        memory_pct: 45.5,
        process_pct: 12.3,
        port_pct: 0.5,
        atom_pct: 1.2,
        run_queue: 0,
        schedulers_online: 8
      }

      result = BeamObservation.to_prompt_string(obs)

      assert result =~ "2024-01-06T10:30:00Z"
      assert result =~ "mem=45.5%"
      assert result =~ "proc=12.3%"
      assert result =~ "port=0.5%"
      assert result =~ "atom=1.2%"
      assert result =~ "rq=0"
      assert result =~ "sched=8"
    end
  end

  describe "format_list/1" do
    test "formats multiple observations" do
      obs1 = %BeamObservation{
        observed_at: ~U[2024-01-06 10:30:00Z],
        memory_pct: 45.0,
        process_pct: 10.0,
        port_pct: 0.5,
        atom_pct: 1.0,
        run_queue: 0,
        schedulers_online: 8
      }

      obs2 = %BeamObservation{
        observed_at: ~U[2024-01-06 10:31:00Z],
        memory_pct: 46.0,
        process_pct: 11.0,
        port_pct: 0.6,
        atom_pct: 1.1,
        run_queue: 1,
        schedulers_online: 8
      }

      result = BeamObservation.format_list([obs1, obs2])

      lines = String.split(result, "\n")
      assert length(lines) == 2
      assert Enum.at(lines, 0) =~ "mem=45.0%"
      assert Enum.at(lines, 1) =~ "mem=46.0%"
    end

    test "returns empty string for empty list" do
      assert BeamObservation.format_list([]) == ""
    end
  end
end
