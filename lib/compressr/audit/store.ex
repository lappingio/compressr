defmodule Compressr.Audit.Store do
  @moduledoc """
  DynamoDB persistence for audit events.

  Events are partitioned by day for efficient time-range queries:

  - Primary key: `pk = "audit#YYYY-MM-DD"`, `sk = "timestamp#uuid"`

  Global secondary indexes (GSI) support querying by user and resource:

  - `gsi_user`: `user_id` (hash) + `timestamp` (range)
  - `gsi_resource`: `resource_key` (hash) + `timestamp` (range)
    where `resource_key = "type#id"`

  In test, the table is created by `Compressr.Test.LocalStack`.
  """

  alias Compressr.Audit.Event

  # ---------------------------------------------------------------------------
  # Write
  # ---------------------------------------------------------------------------

  @doc """
  Persists an audit event to DynamoDB.
  """
  @spec log_event(Event.t()) :: :ok | {:error, term()}
  def log_event(%Event{} = event) do
    item = event_to_item(event)

    case ExAws.Dynamo.put_item(table_name(), item) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Read — by date
  # ---------------------------------------------------------------------------

  @doc """
  Queries audit events for a given date.

  ## Options

  - `:limit` — maximum number of items to return (default 50)
  - `:exclusive_start_key` — pagination cursor from a previous response
  - `:action` — filter to a specific action atom
  """
  @spec query_by_date(Date.t(), keyword()) :: {:ok, [Event.t()], map()}
  def query_by_date(%Date{} = date, opts \\ []) do
    pk = "audit##{Date.to_iso8601(date)}"
    limit = Keyword.get(opts, :limit, 50)
    start_key = Keyword.get(opts, :exclusive_start_key)
    action_filter = Keyword.get(opts, :action)

    query_opts =
      [
        key_condition_expression: "pk = :pk",
        expression_attribute_values: build_date_attr_values(pk, action_filter),
        limit: limit,
        scan_index_forward: false
      ]
      |> maybe_add_start_key(start_key)
      |> maybe_add_action_filter(action_filter)

    execute_query(query_opts)
  end

  # ---------------------------------------------------------------------------
  # Read — by user (scan with filter, since no GSI in test)
  # ---------------------------------------------------------------------------

  @doc """
  Queries audit events for a given user ID.

  Uses a scan with a filter expression. In production, a GSI on `user_id`
  would make this more efficient.

  ## Options

  - `:limit` — maximum number of items to return (default 50)
  - `:exclusive_start_key` — pagination cursor
  """
  @spec query_by_user(String.t(), keyword()) :: {:ok, [Event.t()], map()}
  def query_by_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    start_key = Keyword.get(opts, :exclusive_start_key)

    scan_opts =
      [
        filter_expression: "user_id = :uid AND begins_with(pk, :prefix)",
        expression_attribute_values: [uid: user_id, prefix: "audit#"],
        limit: limit
      ]
      |> maybe_add_start_key(start_key)

    execute_scan(scan_opts)
  end

  # ---------------------------------------------------------------------------
  # Read — by resource
  # ---------------------------------------------------------------------------

  @doc """
  Queries audit events for a given resource type and ID.

  Uses a scan with a filter expression. In production, a GSI on
  `resource_key` would be more efficient.

  ## Options

  - `:limit` — maximum number of items to return (default 50)
  - `:exclusive_start_key` — pagination cursor
  """
  @spec query_by_resource(String.t(), String.t(), keyword()) :: {:ok, [Event.t()], map()}
  def query_by_resource(resource_type, resource_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    start_key = Keyword.get(opts, :exclusive_start_key)

    scan_opts =
      [
        filter_expression:
          "resource_type = :rt AND resource_id = :rid AND begins_with(pk, :prefix)",
        expression_attribute_values: [rt: resource_type, rid: resource_id, prefix: "audit#"],
        limit: limit
      ]
      |> maybe_add_start_key(start_key)

    execute_scan(scan_opts)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}audit"
  end

  defp event_to_item(%Event{} = e) do
    date_str = String.slice(e.timestamp, 0, 10)

    base = %{
      "pk" => "audit##{date_str}",
      "sk" => "#{e.timestamp}##{e.id}",
      "id" => e.id,
      "timestamp" => e.timestamp,
      "action" => Atom.to_string(e.action)
    }

    base
    |> maybe_put("user_id", e.user_id)
    |> maybe_put("user_email", e.user_email)
    |> maybe_put("resource_type", e.resource_type)
    |> maybe_put("resource_id", e.resource_id)
    |> maybe_put("source_ip", e.source_ip)
    |> maybe_put("details", encode_details(e.details))
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp encode_details(nil), do: nil
  defp encode_details(details) when is_map(details), do: Jason.encode!(details)

  defp build_date_attr_values(pk, nil), do: [pk: pk]
  defp build_date_attr_values(pk, action), do: [pk: pk, act: Atom.to_string(action)]

  defp maybe_add_start_key(opts, nil), do: opts

  defp maybe_add_start_key(opts, start_key),
    do: Keyword.put(opts, :exclusive_start_key, start_key)

  defp maybe_add_action_filter(opts, nil), do: opts

  defp maybe_add_action_filter(opts, _action) do
    existing = Keyword.get(opts, :key_condition_expression, "")
    filter = "action = :act"
    combined = if existing == "", do: filter, else: existing

    opts
    |> Keyword.put(:key_condition_expression, combined)
    |> Keyword.put(:filter_expression, filter)
  end

  defp execute_query(opts) do
    result =
      ExAws.Dynamo.query(table_name(), opts)
      |> ExAws.request!()

    events =
      result
      |> Map.get("Items", [])
      |> Enum.map(&item_to_event/1)

    pagination = extract_pagination(result)
    {:ok, events, pagination}
  end

  defp execute_scan(opts) do
    result =
      ExAws.Dynamo.scan(table_name(), opts)
      |> ExAws.request!()

    events =
      result
      |> Map.get("Items", [])
      |> Enum.map(&item_to_event/1)

    pagination = extract_pagination(result)
    {:ok, events, pagination}
  end

  defp extract_pagination(result) do
    case Map.get(result, "LastEvaluatedKey") do
      nil -> %{}
      key -> %{last_evaluated_key: key}
    end
  end

  defp item_to_event(item) do
    %Event{
      id: get_s(item, "id"),
      timestamp: get_s(item, "timestamp"),
      action: item |> get_s("action") |> String.to_existing_atom(),
      user_id: get_s(item, "user_id"),
      user_email: get_s(item, "user_email"),
      resource_type: get_s(item, "resource_type"),
      resource_id: get_s(item, "resource_id"),
      source_ip: get_s(item, "source_ip"),
      details: item |> get_s("details") |> decode_details()
    }
  end

  defp get_s(item, key) do
    case Map.get(item, key) do
      %{"S" => val} -> val
      _ -> nil
    end
  end

  defp decode_details(nil), do: nil

  defp decode_details(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} -> map
      _ -> nil
    end
  end
end
