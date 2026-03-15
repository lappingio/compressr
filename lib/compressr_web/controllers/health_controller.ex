defmodule CompressrWeb.HealthController do
  use CompressrWeb, :controller

  @doc """
  Liveness health check endpoint.
  Returns 200 when the node is healthy, 503 when degraded.
  """
  def health(conn, _params) do
    health_data = Compressr.Health.check()

    status_code = if health_data.status == :ok, do: 200, else: 503
    status_string = if health_data.status == :ok, do: "healthy", else: "unhealthy"

    conn
    |> put_status(status_code)
    |> json(%{
      status: status_string,
      node: to_string(health_data.node),
      uptime_seconds: health_data.uptime_seconds,
      memory_mb: Float.round(health_data.memory.total / 1_048_576, 1),
      connected_peers: health_data.peer_count
    })
  end

  @doc """
  Readiness check endpoint.
  Returns 200 when all subsystems are ready, 503 otherwise.
  """
  def ready(conn, _params) do
    readiness = Compressr.Health.Readiness.check()

    status_code = if readiness.status == :ready, do: 200, else: 503

    subsystems =
      Map.new(readiness.subsystems, fn {k, v} ->
        {k, if(v, do: "ready", else: "not_ready")}
      end)

    conn
    |> put_status(status_code)
    |> json(%{
      status: to_string(readiness.status),
      node: to_string(node()),
      subsystems: subsystems
    })
  end
end
