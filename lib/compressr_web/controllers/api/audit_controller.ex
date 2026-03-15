defmodule CompressrWeb.Api.AuditController do
  use CompressrWeb, :controller

  alias Compressr.Audit
  alias Compressr.Audit.Event

  action_fallback CompressrWeb.Api.FallbackController

  @doc """
  GET /api/v1/system/audit

  Query audit events with optional filters:

  - `date` — ISO 8601 date string (defaults to today)
  - `user_id` — filter by user ID (uses scan)
  - `resource_type` + `resource_id` — filter by resource (uses scan)
  - `action` — filter by action name
  - `limit` — max results (default 50)
  """
  def index(conn, params) do
    limit = parse_limit(params)

    {events, pagination} =
      cond do
        user_id = params["user_id"] ->
          {:ok, events, pagination} = Audit.query_by_user(user_id, limit: limit)
          {events, pagination}

        params["resource_type"] && params["resource_id"] ->
          {:ok, events, pagination} =
            Audit.query_by_resource(
              params["resource_type"],
              params["resource_id"],
              limit: limit
            )

          {events, pagination}

        true ->
          date = parse_date(params["date"])
          opts = [limit: limit]

          opts =
            if action = params["action"] do
              Keyword.put(opts, :action, String.to_existing_atom(action))
            else
              opts
            end

          {:ok, events, pagination} = Audit.query_by_date(date, opts)
          {events, pagination}
      end

    items = Enum.map(events, &Event.to_map/1)

    response = %{items: items, count: length(items)}

    response =
      case Map.get(pagination, :last_evaluated_key) do
        nil -> response
        key -> Map.put(response, :next_cursor, key)
      end

    conn
    |> put_status(200)
    |> json(response)
  end

  defp parse_date(nil), do: Date.utc_today()

  defp parse_date(date_str) do
    case Date.from_iso8601(date_str) do
      {:ok, date} -> date
      _ -> Date.utc_today()
    end
  end

  defp parse_limit(params) do
    case params["limit"] do
      nil -> 50
      val when is_binary(val) -> String.to_integer(val)
      val when is_integer(val) -> val
    end
  end
end
