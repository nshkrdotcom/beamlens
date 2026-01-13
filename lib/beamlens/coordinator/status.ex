defmodule Beamlens.Coordinator.Status do
  @moduledoc """
  Status information for a running Coordinator.

  Returned by `Beamlens.Coordinator.status/1`.
  """

  defstruct [:running, :notification_count, :unread_count, :iteration]

  @type t :: %__MODULE__{
          running: boolean(),
          notification_count: non_neg_integer(),
          unread_count: non_neg_integer(),
          iteration: non_neg_integer()
        }
end
