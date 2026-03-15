defmodule Compressr.Drain.ShutdownHandler do
  @moduledoc """
  Hooks into OTP shutdown to trigger graceful drain.

  This GenServer traps exits and initiates a graceful drain via
  `Compressr.Drain.initiate/0` when a termination signal is received.
  It is started early in the supervision tree so it can coordinate
  shutdown of other children.
  """

  use GenServer

  require Logger

  @default_drain_timeout 30_000

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    state = %{
      drain_timeout: Keyword.get(opts, :drain_timeout, drain_timeout()),
      drain_server: Keyword.get(opts, :drain_server, Compressr.Drain)
    }

    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("ShutdownHandler terminating (reason: #{inspect(reason)}), initiating drain")

    try do
      Compressr.Drain.initiate(state.drain_server)
    rescue
      e ->
        Logger.error("Drain failed during shutdown: #{inspect(e)}")
    catch
      kind, reason ->
        Logger.error("Drain failed during shutdown: #{inspect(kind)} #{inspect(reason)}")
    end

    :ok
  end

  defp drain_timeout do
    Application.get_env(:compressr, :drain_timeout, @default_drain_timeout)
  end
end
