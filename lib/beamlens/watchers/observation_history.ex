defmodule Beamlens.Watchers.ObservationHistory do
  @moduledoc """
  Generic ring buffer for storing watcher observations.

  Maintains a rolling window of observations for baseline analysis.
  Observations are stored newest-first and automatically pruned
  when the window size is exceeded.
  """

  @default_window_size 60

  @enforce_keys [:window_size]
  defstruct [
    :window_size,
    observations: [],
    total_count: 0
  ]

  @type t :: %__MODULE__{
          window_size: pos_integer(),
          observations: [any()],
          total_count: non_neg_integer()
        }

  @doc """
  Creates a new empty observation history.

  ## Options

    * `:window_size` - Maximum number of observations to retain (default: 60)
  """
  def new(opts \\ []) do
    window_size = Keyword.get(opts, :window_size, @default_window_size)

    %__MODULE__{
      window_size: window_size,
      observations: [],
      total_count: 0
    }
  end

  @doc """
  Adds an observation to the history.

  The observation is prepended to the list (newest first).
  If the window size is exceeded, the oldest observation is dropped.
  """
  def add(%__MODULE__{} = history, observation) do
    new_observations =
      [observation | history.observations]
      |> Enum.take(history.window_size)

    %{history | observations: new_observations, total_count: history.total_count + 1}
  end

  @doc """
  Returns the number of observations currently stored.
  """
  def count(%__MODULE__{observations: observations}), do: length(observations)

  @doc """
  Returns true if the history is empty.
  """
  def empty?(%__MODULE__{observations: []}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Returns the most recent observation, or nil if empty.
  """
  def latest(%__MODULE__{observations: []}), do: nil
  def latest(%__MODULE__{observations: [head | _]}), do: head

  @doc """
  Returns the oldest observation in the window, or nil if empty.
  """
  def oldest(%__MODULE__{observations: []}), do: nil
  def oldest(%__MODULE__{observations: observations}), do: List.last(observations)

  @doc """
  Returns observations as a list, newest first.
  """
  def to_list(%__MODULE__{observations: observations}), do: observations

  @doc """
  Returns observations as a list, oldest first.
  """
  def to_list_oldest_first(%__MODULE__{observations: observations}) do
    Enum.reverse(observations)
  end

  @doc """
  Returns the most recent n observations, newest first.
  """
  def take(%__MODULE__{observations: observations}, n) when is_integer(n) and n > 0 do
    Enum.take(observations, n)
  end
end
