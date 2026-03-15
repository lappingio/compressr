defmodule Compressr.Audit.Logger do
  @moduledoc """
  Emits audit events as structured JSON log lines.

  Audit log lines are written at the `:info` level with a `[audit]` prefix
  so they can be routed separately from application logs by log aggregators.
  """

  require Logger

  alias Compressr.Audit.Event

  @doc """
  Emits an audit event as a structured JSON log line.
  """
  @spec emit(Event.t()) :: :ok
  def emit(%Event{} = event) do
    log_data = %{
      audit: true,
      id: event.id,
      timestamp: event.timestamp,
      action: Atom.to_string(event.action),
      user_id: event.user_id,
      user_email: event.user_email,
      resource_type: event.resource_type,
      resource_id: event.resource_id,
      source_ip: event.source_ip,
      details: event.details
    }

    Logger.info(fn -> "[audit] #{Jason.encode!(log_data)}" end)
    :ok
  end
end
