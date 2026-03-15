defmodule Compressr.Source.HEC do
  @moduledoc """
  Splunk HTTP Event Collector (HEC) compatible source.

  Accepts events via HTTP endpoints compatible with Splunk's HEC protocol:
  - `/services/collector/event` — JSON events
  - `/services/collector/raw` — raw text events
  - `/services/collector/health` — health check

  Configuration:
    - `port` - HTTP port to listen on (integer, required)
    - `token` - HEC authentication token (string, optional; nil = no auth)
    - `path` - base path prefix (string, optional; default: "/services/collector")
  """

  @behaviour Compressr.Source

  @impl true
  def validate_config(config) do
    cond do
      not is_integer(Map.get(config, "port")) ->
        {:error, {:missing_fields, ["port"]}}

      true ->
        :ok
    end
  end

  @impl true
  def init(config) do
    {:ok,
     %{
       config: config,
       token: Map.get(config, "token"),
       port: Map.get(config, "port")
     }}
  end

  @impl true
  def handle_data(data, state) do
    # Delegate to the appropriate handler based on content
    # In practice, the HTTP endpoint handler will call specific functions
    {:ok, [], state}
    |> then(fn _ ->
      # Default: try JSON, then raw
      case handle_json_event(data, state) do
        {:ok, events, new_state} -> {:ok, events, new_state}
        {:error, _} -> handle_raw_event(data, state)
      end
    end)
  end

  @impl true
  def stop(_state) do
    :ok
  end

  @doc """
  Handle a JSON HEC event request.

  Accepts JSON body from `/services/collector/event`.
  Returns `{:ok, events, state}` or `{:error, reason}`.
  """
  @spec handle_json_event(binary(), map()) :: {:ok, [map()], map()} | {:error, term()}
  def handle_json_event(body, state) do
    case Jason.decode(body) do
      {:ok, %{"event" => event_data} = payload} ->
        raw =
          if is_binary(event_data) do
            event_data
          else
            Jason.encode!(event_data)
          end

        event =
          Compressr.Event.new(raw, %{})
          |> maybe_set_time(payload)
          |> maybe_set_fields(payload)

        {:ok, [event], state}

      {:ok, _} ->
        {:error, :invalid_hec_payload}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Handle a raw HEC event request.

  Accepts raw text from `/services/collector/raw`.
  Each line becomes a separate event.
  """
  @spec handle_raw_event(binary(), map()) :: {:ok, [map()], map()}
  def handle_raw_event(body, state) do
    events =
      body
      |> String.split("\n", trim: true)
      |> Enum.map(&Compressr.Event.from_raw/1)

    {:ok, events, state}
  end

  @doc """
  Authenticate a request against the configured HEC token.

  Returns `:ok` if authenticated, `{:error, :unauthorized}` if not.
  When no token is configured (nil or empty), all requests are allowed.
  """
  @spec authenticate(String.t() | nil, map()) :: :ok | {:error, :unauthorized}
  def authenticate(_provided_token, %{token: nil}), do: :ok
  def authenticate(_provided_token, %{token: ""}), do: :ok

  def authenticate(provided_token, %{token: expected_token}) do
    # Strip "Splunk " prefix if present (HEC standard)
    clean_token =
      case provided_token do
        "Splunk " <> token -> token
        token when is_binary(token) -> token
        _ -> ""
      end

    if Plug.Crypto.secure_compare(clean_token, expected_token) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  @doc """
  Build a standard HEC success response.
  """
  @spec success_response() :: map()
  def success_response do
    %{"text" => "Success", "code" => 0}
  end

  @doc """
  Build a standard HEC error response.
  """
  @spec error_response(integer(), String.t()) :: map()
  def error_response(code, text) do
    %{"text" => text, "code" => code}
  end

  # --- Private ---

  defp maybe_set_time(event, %{"time" => time}) when is_number(time) do
    Map.put(event, "_time", trunc(time))
  end

  defp maybe_set_time(event, _payload), do: event

  defp maybe_set_fields(event, payload) do
    payload
    |> Map.take(["host", "source", "sourcetype", "index"])
    |> Enum.reduce(event, fn {k, v}, acc -> Map.put(acc, k, v) end)
  end
end
