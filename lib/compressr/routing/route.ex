defmodule Compressr.Routing.Route do
  @moduledoc """
  Represents a single route entry in the routing table.

  A route defines how events matching a filter are directed to a pipeline
  and destination. Routes are evaluated in ascending position order.

  ## Fields

  - `id` — unique identifier (string)
  - `name` — unique, case-sensitive route name
  - `filter` — a function `(event -> boolean)` evaluated against incoming events
  - `pipeline_id` — reference to the processing pipeline
  - `destination_id` — reference to the output destination
  - `final` — when true, matched events stop evaluation (default: true)
  - `enabled` — when false, route is skipped during evaluation (default: true)
  - `position` — integer determining evaluation order (ascending)
  - `description` — optional human-readable description
  """

  @enforce_keys [:id, :name, :filter, :pipeline_id, :destination_id, :position]
  defstruct [
    :id,
    :name,
    :filter,
    :pipeline_id,
    :destination_id,
    :position,
    :description,
    final: true,
    enabled: true
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          filter: (map() -> boolean()),
          pipeline_id: String.t(),
          destination_id: String.t(),
          final: boolean(),
          enabled: boolean(),
          position: integer(),
          description: String.t() | nil
        }

  @doc """
  Creates a new Route struct.

  ## Options

  All fields from the struct are accepted as keyword options. The following
  are required: `:id`, `:name`, `:filter`, `:pipeline_id`, `:destination_id`,
  `:position`.
  """
  @spec new(keyword()) :: t()
  def new(attrs) when is_list(attrs) do
    struct!(__MODULE__, attrs)
  end

  @doc """
  Returns true if the given event matches this route's filter.
  """
  @spec matches?(t(), map()) :: boolean()
  def matches?(%__MODULE__{filter: filter}, event) when is_map(event) do
    filter.(event)
  end
end
