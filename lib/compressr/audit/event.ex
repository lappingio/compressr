defmodule Compressr.Audit.Event do
  @moduledoc """
  Struct representing a single audit log entry.
  """

  @enforce_keys [:id, :timestamp, :action]
  defstruct [
    :id,
    :timestamp,
    :action,
    :user_id,
    :user_email,
    :resource_type,
    :resource_id,
    :source_ip,
    :details
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          timestamp: String.t(),
          action: atom(),
          user_id: String.t() | nil,
          user_email: String.t() | nil,
          resource_type: String.t() | nil,
          resource_id: String.t() | nil,
          source_ip: String.t() | nil,
          details: map() | nil
        }

  @doc """
  Builds an audit event struct from the given action, user info, and metadata.
  """
  @spec build(atom(), map() | nil, map()) :: t()
  def build(action, user, metadata \\ %{}) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    id = generate_id()

    %__MODULE__{
      id: id,
      timestamp: now,
      action: action,
      user_id: extract_user_field(user, :user_id, :sub),
      user_email: extract_user_field(user, :user_email, :email),
      resource_type: Map.get(metadata, :resource_type),
      resource_id: Map.get(metadata, :resource_id),
      source_ip: Map.get(metadata, :source_ip),
      details: Map.get(metadata, :details)
    }
  end

  @doc """
  Converts an event struct to a plain map suitable for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
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
  end

  defp extract_user_field(nil, _primary, _fallback), do: nil

  defp extract_user_field(user, primary, fallback) when is_map(user) do
    Map.get(user, primary) || Map.get(user, fallback)
  end

  defp generate_id do
    Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end
end
