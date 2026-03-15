defmodule Compressr.Audit do
  @moduledoc """
  Audit logging context module.

  Provides a single entry point for recording audit events. Every
  authentication event, configuration change, and administrative action
  should flow through `log/3`.

  Audit events are persisted to DynamoDB (via `Compressr.Audit.Store`) and
  also emitted as structured log lines (via `Compressr.Audit.Logger`).
  """

  alias Compressr.Audit.{Store, Event}

  @type action ::
          :login
          | :logout
          | :login_failed
          | :config_created
          | :config_updated
          | :config_deleted
          | :token_created
          | :token_revoked
          | :source_started
          | :source_stopped
          | :replay_initiated

  @type user_info :: %{
          optional(:user_id) => String.t(),
          optional(:user_email) => String.t()
        }

  @doc """
  Logs an audit event.

  ## Parameters

  - `action` — one of the defined audit actions
  - `user` — a map or struct with `:user_id` and/or `:user_email`, or `nil` for
    unauthenticated events (e.g. `:login_failed`)
  - `metadata` — a map of additional context:
    - `:resource_type` — e.g. `"source"`, `"destination"`, `"pipeline"`
    - `:resource_id` — the ID of the affected resource
    - `:source_ip` — the client IP address
    - `:details` — arbitrary map of extra information

  Returns `{:ok, event}` on success, `{:error, reason}` on failure.
  """
  @spec log(action(), user_info() | nil, map()) :: {:ok, Event.t()} | {:error, term()}
  def log(action, user, metadata \\ %{}) do
    event = Event.build(action, user, metadata)

    Compressr.Audit.Logger.emit(event)

    case Store.log_event(event) do
      :ok -> {:ok, event}
      {:error, _} = error -> error
    end
  end

  @doc """
  Query audit events by date range.

  See `Compressr.Audit.Store.query_by_date/2` for options.
  """
  @spec query_by_date(Date.t(), keyword()) :: {:ok, [Event.t()], map()}
  def query_by_date(date, opts \\ []) do
    Store.query_by_date(date, opts)
  end

  @doc """
  Query audit events by user ID.

  See `Compressr.Audit.Store.query_by_user/2` for options.
  """
  @spec query_by_user(String.t(), keyword()) :: {:ok, [Event.t()], map()}
  def query_by_user(user_id, opts \\ []) do
    Store.query_by_user(user_id, opts)
  end

  @doc """
  Query audit events by resource type and ID.

  See `Compressr.Audit.Store.query_by_resource/3` for options.
  """
  @spec query_by_resource(String.t(), String.t(), keyword()) :: {:ok, [Event.t()], map()}
  def query_by_resource(resource_type, resource_id, opts \\ []) do
    Store.query_by_resource(resource_type, resource_id, opts)
  end
end
