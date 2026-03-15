defmodule Compressr.Routing.DevNull do
  @moduledoc """
  A well-known destination that silently discards all events routed to it.

  The DevNull destination requires no configuration and is available immediately
  on system startup. It can be used as any route's destination for testing,
  validation, or intentional event dropping.
  """

  @destination_id "devnull"

  @doc """
  Returns the well-known DevNull destination ID.
  """
  @spec destination_id() :: String.t()
  def destination_id, do: @destination_id
end
