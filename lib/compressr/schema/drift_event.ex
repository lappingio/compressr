defmodule Compressr.Schema.DriftEvent do
  @moduledoc """
  Represents a schema drift event.

  Drift events are created when the structure of incoming events
  differs from the learned baseline schema.
  """

  @type drift_type :: :new_field | :missing_field | :type_change

  @type t :: %__MODULE__{
          source_id: String.t(),
          timestamp: DateTime.t(),
          drift_type: drift_type(),
          field_name: String.t(),
          old_value: term(),
          new_value: term(),
          sample_event: map() | nil
        }

  @enforce_keys [:source_id, :timestamp, :drift_type, :field_name]
  defstruct [
    :source_id,
    :timestamp,
    :drift_type,
    :field_name,
    :old_value,
    :new_value,
    :sample_event
  ]

  @doc """
  Creates a new drift event.
  """
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      source_id: Map.fetch!(attrs, :source_id),
      timestamp: Map.get(attrs, :timestamp, DateTime.utc_now()),
      drift_type: Map.fetch!(attrs, :drift_type),
      field_name: Map.fetch!(attrs, :field_name),
      old_value: Map.get(attrs, :old_value),
      new_value: Map.get(attrs, :new_value),
      sample_event: Map.get(attrs, :sample_event)
    }
  end
end
