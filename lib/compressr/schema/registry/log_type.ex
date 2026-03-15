defmodule Compressr.Schema.Registry.LogType do
  @moduledoc """
  Struct representing a detected log type within a source stream.

  A log type is identified by its structural fingerprint (hash of sorted
  field names) and tracks its own independent schema, volume, and lifecycle.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          source_id: String.t(),
          fingerprint: binary(),
          classification_method: atom(),
          first_seen: DateTime.t(),
          last_seen: DateTime.t(),
          event_count: non_neg_integer(),
          schema: map()
        }

  @enforce_keys [:id, :source_id, :fingerprint]
  defstruct [
    :id,
    :name,
    :source_id,
    :fingerprint,
    classification_method: :structural,
    first_seen: nil,
    last_seen: nil,
    event_count: 0,
    schema: %{}
  ]

  @doc """
  Creates a new LogType struct with sensible defaults.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    %__MODULE__{
      id: Map.fetch!(attrs, :id),
      name: Map.get(attrs, :name, Map.fetch!(attrs, :id)),
      source_id: Map.fetch!(attrs, :source_id),
      fingerprint: Map.fetch!(attrs, :fingerprint),
      classification_method: Map.get(attrs, :classification_method, :structural),
      first_seen: Map.get(attrs, :first_seen, now),
      last_seen: Map.get(attrs, :last_seen, now),
      event_count: Map.get(attrs, :event_count, 0),
      schema: Map.get(attrs, :schema, %{})
    }
  end

  @doc """
  Updates the log type after observing a new event.

  Increments event_count and updates last_seen.
  """
  @spec record_event(t()) :: t()
  def record_event(%__MODULE__{} = log_type) do
    %{log_type | event_count: log_type.event_count + 1, last_seen: DateTime.utc_now()}
  end
end
