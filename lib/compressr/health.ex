defmodule Compressr.Health do
  @moduledoc """
  Collects node health data for liveness checks.
  """

  @memory_threshold_bytes 1_073_741_824  # 1 GB

  @doc """
  Returns a map of health data for the current node.
  """
  def check do
    memory = :erlang.memory()
    total_memory = memory[:total]
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    status =
      if total_memory > @memory_threshold_bytes do
        :degraded
      else
        :ok
      end

    %{
      status: status,
      node: node(),
      uptime_seconds: div(uptime_ms, 1000),
      memory: %{
        total: memory[:total],
        used: memory[:processes] + memory[:system]
      },
      peers: Node.list(),
      peer_count: length(Node.list())
    }
  end
end
