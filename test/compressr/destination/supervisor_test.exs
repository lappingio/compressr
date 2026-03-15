defmodule Compressr.Destination.SupervisorTest do
  use ExUnit.Case, async: false

  alias Compressr.Destination.Supervisor, as: DestSupervisor
  alias Compressr.Destination.Config

  # The Destination.Supervisor is not started in the application supervision tree,
  # so we start it manually for tests.
  setup do
    case DynamicSupervisor.start_link(strategy: :one_for_one, name: DestSupervisor) do
      {:ok, pid} -> %{sup_pid: pid}
      {:error, {:already_started, pid}} -> %{sup_pid: pid}
    end
  end

  defp make_config(id, type \\ "devnull") do
    %Config{
      id: id,
      name: "Test #{id}",
      type: type,
      config: %{},
      enabled: true,
      backpressure_mode: :block
    }
  end

  describe "start_destination/1" do
    test "starts a devnull destination" do
      config = make_config("sup-test-1")
      assert {:ok, pid} = DestSupervisor.start_destination(config)
      assert Process.alive?(pid)

      # Clean up
      DestSupervisor.stop_destination("sup-test-1")
    end

    test "starts an s3 destination" do
      config = make_config("sup-test-s3", "s3")
      config = %{config | config: %{
        "bucket" => "compressr-test-events",
        "prefix" => "test/",
        "region" => "us-east-1"
      }}

      assert {:ok, pid} = DestSupervisor.start_destination(config)
      assert Process.alive?(pid)

      DestSupervisor.stop_destination("sup-test-s3")
    end

    test "raises for unknown destination type" do
      config = make_config("sup-test-bad", "unknown_type")

      assert_raise RuntimeError, ~r/Unknown destination type/, fn ->
        DestSupervisor.start_destination(config)
      end
    end
  end

  describe "stop_destination/1" do
    test "stops a running destination" do
      config = make_config("sup-stop-1")
      {:ok, pid} = DestSupervisor.start_destination(config)
      assert Process.alive?(pid)

      assert :ok = DestSupervisor.stop_destination("sup-stop-1")
      refute Process.alive?(pid)
    end

    test "returns error when destination not found" do
      assert {:error, :not_found} = DestSupervisor.stop_destination("nonexistent-dest")
    end
  end

  describe "multiple destinations" do
    test "can run multiple destinations simultaneously" do
      config1 = make_config("sup-multi-1")
      config2 = make_config("sup-multi-2")

      {:ok, pid1} = DestSupervisor.start_destination(config1)
      {:ok, pid2} = DestSupervisor.start_destination(config2)

      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
      assert pid1 != pid2

      DestSupervisor.stop_destination("sup-multi-1")
      DestSupervisor.stop_destination("sup-multi-2")
    end
  end
end
