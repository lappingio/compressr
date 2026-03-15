defmodule Compressr.Schema.Alerter do
  @moduledoc """
  Broadcasts schema drift events via Phoenix.PubSub.

  Other systems (LiveView, webhooks) can subscribe to receive
  real-time drift notifications.
  """

  alias Compressr.Schema.DriftEvent

  @topic "schema:drift"

  @doc """
  Broadcast a drift event to all subscribers.
  """
  @spec broadcast_drift(DriftEvent.t()) :: :ok | {:error, term()}
  def broadcast_drift(%DriftEvent{} = drift_event) do
    Phoenix.PubSub.broadcast(
      Compressr.PubSub,
      @topic,
      {:schema_drift, drift_event}
    )
  end

  @doc """
  Broadcast a drift event for a specific source topic.
  """
  @spec broadcast_drift(DriftEvent.t(), String.t()) :: :ok | {:error, term()}
  def broadcast_drift(%DriftEvent{} = drift_event, source_id) do
    # Broadcast to both the general topic and source-specific topic
    Phoenix.PubSub.broadcast(
      Compressr.PubSub,
      @topic,
      {:schema_drift, drift_event}
    )

    Phoenix.PubSub.broadcast(
      Compressr.PubSub,
      "#{@topic}:#{source_id}",
      {:schema_drift, drift_event}
    )
  end

  @doc """
  Subscribe to all schema drift events.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Compressr.PubSub, @topic)
  end

  @doc """
  Subscribe to drift events for a specific source.
  """
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(source_id) do
    Phoenix.PubSub.subscribe(Compressr.PubSub, "#{@topic}:#{source_id}")
  end
end
