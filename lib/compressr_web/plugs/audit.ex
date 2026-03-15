defmodule CompressrWeb.Plugs.Audit do
  @moduledoc """
  Plug that automatically logs API requests as audit events.

  Records HTTP method, path, authenticated user, response status code,
  and request duration for every request that passes through the pipeline.

  ## Usage

  Add to a pipeline in your router:

      pipeline :api do
        plug :accepts, ["json"]
        plug CompressrWeb.Plugs.Audit
      end
  """

  import Plug.Conn
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    start_time = System.monotonic_time(:millisecond)

    register_before_send(conn, fn conn ->
      duration = System.monotonic_time(:millisecond) - start_time
      log_request(conn, duration)
      conn
    end)
  end

  defp log_request(conn, duration) do
    user = conn.assigns[:current_user]

    user_info =
      if user do
        %{user_id: Map.get(user, :sub), user_email: Map.get(user, :email)}
      else
        nil
      end

    metadata = %{
      source_ip: format_ip(conn.remote_ip),
      details: %{
        "method" => conn.method,
        "path" => conn.request_path,
        "status" => conn.status,
        "duration_ms" => duration
      }
    }

    action = infer_action(conn.method, conn.request_path, conn.status)

    # Fire-and-forget — do not block the response on audit persistence
    Task.start(fn ->
      Compressr.Audit.log(action, user_info, metadata)
    end)
  end

  defp infer_action("POST", _path, status) when status in 200..299, do: :config_created
  defp infer_action("PUT", _path, status) when status in 200..299, do: :config_updated
  defp infer_action("PATCH", _path, status) when status in 200..299, do: :config_updated
  defp infer_action("DELETE", _path, status) when status in 200..299, do: :config_deleted
  defp infer_action(_method, _path, 401), do: :login_failed
  defp infer_action(_method, _path, _status), do: :config_updated

  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  defp format_ip({a, b, c, d, e, f, g, h}),
    do: Enum.map_join([a, b, c, d, e, f, g, h], ":", &Integer.to_string(&1, 16))

  defp format_ip(_), do: "unknown"
end
