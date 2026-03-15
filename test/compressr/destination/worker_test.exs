defmodule Compressr.Destination.WorkerTest do
  use ExUnit.Case, async: true

  alias Compressr.Destination.Worker
  alias Compressr.Destination.Config
  alias Compressr.Destination.DevNull

  describe "start_link/1 and destination_id/1" do
    test "starts a worker with DevNull and returns destination_id" do
      config = %Config{
        id: "worker-test-1",
        name: "Test DevNull",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, pid} = Worker.start_link({DevNull, config})
      assert Process.alive?(pid)
      assert Worker.destination_id(pid) == "worker-test-1"

      GenServer.stop(pid)
    end
  end

  describe "send_batch/2" do
    test "sends a batch of events through the worker" do
      config = %Config{
        id: "worker-batch-1",
        name: "Batch Test",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, pid} = Worker.start_link({DevNull, config})

      events = [
        %{"_raw" => "event1", "_time" => 1000},
        %{"_raw" => "event2", "_time" => 1001}
      ]

      assert :ok = GenServer.call(pid, {:send_batch, events})

      GenServer.stop(pid)
    end

    test "handles multiple batches" do
      config = %Config{
        id: "worker-multi-batch",
        name: "Multi Batch",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, pid} = Worker.start_link({DevNull, config})

      for i <- 1..5 do
        events = [%{"_raw" => "event-#{i}", "_time" => 1000 + i}]
        assert :ok = GenServer.call(pid, {:send_batch, events})
      end

      GenServer.stop(pid)
    end
  end

  describe "flush/1" do
    test "flushes the worker" do
      config = %Config{
        id: "worker-flush-1",
        name: "Flush Test",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, pid} = Worker.start_link({DevNull, config})
      assert :ok = GenServer.call(pid, :flush)

      GenServer.stop(pid)
    end
  end

  describe "init failure" do
    test "returns stop when module init fails" do
      # Create a module that fails on init
      defmodule FailInit do
        @behaviour Compressr.Destination

        def init(_config), do: {:error, :test_failure}
        def send_batch(_events, _state), do: {:ok, nil}
        def flush(_state), do: {:ok, nil}
        def stop(_state), do: :ok
        def healthy?(_state), do: false
      end

      config = %Config{
        id: "worker-fail-init",
        name: "Fail Init",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      # GenServer.start_link with {:stop, reason} sends an EXIT to the caller,
      # so we need to trap exits to receive it as a message
      Process.flag(:trap_exit, true)
      assert {:error, :test_failure} = Worker.start_link({FailInit, config})
    end
  end

  describe "send_batch error" do
    test "returns error tuple when send_batch fails" do
      defmodule FailSend do
        @behaviour Compressr.Destination

        def init(_config), do: {:ok, %{}}
        def send_batch(_events, state), do: {:error, :write_failed, state}
        def flush(state), do: {:ok, state}
        def stop(_state), do: :ok
        def healthy?(_state), do: false
      end

      config = %Config{
        id: "worker-fail-send",
        name: "Fail Send",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, pid} = Worker.start_link({FailSend, config})

      assert {:error, :write_failed} = GenServer.call(pid, {:send_batch, [%{"test" => true}]})

      GenServer.stop(pid)
    end
  end

  describe "terminate/2" do
    test "calls module stop on termination" do
      config = %Config{
        id: "worker-term-1",
        name: "Terminate Test",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, pid} = Worker.start_link({DevNull, config})
      ref = Process.monitor(pid)
      GenServer.stop(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  describe "nil config handling" do
    test "handles nil config field by defaulting to empty map" do
      config = %Config{
        id: "worker-nil-cfg",
        name: "Nil Config",
        type: "devnull",
        config: nil,
        enabled: true,
        backpressure_mode: :block
      }

      {:ok, pid} = Worker.start_link({DevNull, config})
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
