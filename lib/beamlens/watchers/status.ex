defmodule Beamlens.Watchers.Status do
  @moduledoc """
  Status information for a running watcher.

  Returned by `Beamlens.Watchers.Server.status/1`.
  """

  @enforce_keys [:watcher, :cron, :run_count, :running]
  defstruct [:watcher, :cron, :next_run_at, :last_run_at, :run_count, :running, :name]

  @type t :: %__MODULE__{
          watcher: atom(),
          cron: String.t(),
          next_run_at: NaiveDateTime.t() | nil,
          last_run_at: NaiveDateTime.t() | nil,
          run_count: non_neg_integer(),
          running: boolean(),
          name: atom() | nil
        }
end
