defmodule Compressr.Source.WorkerTest do
  use ExUnit.Case, async: false

  alias Compressr.Source.Worker

  describe "start_link/1 and send_data/2" do
    test "starts a syslog worker and processes data" do
      config = %{
        "id" => "sw-test-1",
        "type" => "syslog",
        "config" => %{"udp_port" => 9999, "protocol" => "udp"}
      }

      {:ok, pid} = Worker.start_link({Compressr.Source.Syslog, config})
      assert Process.alive?(pid)

      syslog_msg = "<34>Oct 11 22:14:15 mymachine su: 'su root' failed"
      {:ok, events} = Worker.send_data("sw-test-1", syslog_msg)

      assert is_list(events)
      assert length(events) == 1

      [event] = events
      assert event["__inputId"] == "sw-test-1"
      assert event["hostname"] == "mymachine"

      GenServer.stop(pid)
    end

    test "tags events with source ID" do
      config = %{
        "id" => "sw-tag-test",
        "type" => "syslog",
        "config" => %{"udp_port" => 9998, "protocol" => "udp"}
      }

      {:ok, pid} = Worker.start_link({Compressr.Source.Syslog, config})

      {:ok, events} = Worker.send_data("sw-tag-test", "plain text message")
      assert length(events) == 1

      [event] = events
      assert event["__inputId"] == "sw-tag-test"

      GenServer.stop(pid)
    end

    test "handles multiple messages split by newline" do
      config = %{
        "id" => "sw-multi-msg",
        "type" => "syslog",
        "config" => %{"udp_port" => 9997, "protocol" => "udp"}
      }

      {:ok, pid} = Worker.start_link({Compressr.Source.Syslog, config})

      data = "message one\nmessage two\nmessage three"
      {:ok, events} = Worker.send_data("sw-multi-msg", data)

      assert length(events) == 3
      Enum.each(events, fn event ->
        assert event["__inputId"] == "sw-multi-msg"
      end)

      GenServer.stop(pid)
    end
  end

  describe "init failure" do
    test "returns error when module init fails" do
      defmodule FailingSource do
        @behaviour Compressr.Source

        def init(_config), do: {:error, :init_failed}
        def handle_data(_data, _state), do: {:ok, [], nil}
        def stop(_state), do: :ok
      end

      config = %{
        "id" => "sw-fail-init",
        "type" => "custom",
        "config" => %{}
      }

      Process.flag(:trap_exit, true)
      assert {:error, :init_failed} = Worker.start_link({FailingSource, config})
    end
  end

  describe "handle_data error" do
    test "returns error when handle_data fails" do
      defmodule ErrorSource do
        @behaviour Compressr.Source

        def init(_config), do: {:ok, %{}}
        def handle_data(_data, _state), do: {:error, :parse_failed}
        def stop(_state), do: :ok
      end

      config = %{
        "id" => "sw-err-data",
        "type" => "custom",
        "config" => %{}
      }

      {:ok, pid} = Worker.start_link({ErrorSource, config})

      assert {:error, :parse_failed} = Worker.send_data("sw-err-data", "bad data")

      GenServer.stop(pid)
    end
  end

  describe "terminate/2" do
    test "calls module stop on termination" do
      config = %{
        "id" => "sw-term-test",
        "type" => "syslog",
        "config" => %{"udp_port" => 9996, "protocol" => "udp"}
      }

      {:ok, pid} = Worker.start_link({Compressr.Source.Syslog, config})
      ref = Process.monitor(pid)
      GenServer.stop(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end
  end

  describe "nil config handling" do
    test "handles nil config field by defaulting to empty map" do
      config = %{
        "id" => "sw-nil-cfg",
        "type" => "syslog",
        "config" => nil
      }

      {:ok, pid} = Worker.start_link({Compressr.Source.Syslog, config})
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
