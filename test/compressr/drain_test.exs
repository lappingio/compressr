defmodule Compressr.DrainTest do
  use ExUnit.Case, async: true

  alias Compressr.Drain
  alias Compressr.Health.Readiness

  setup do
    # Start isolated Readiness and Drain servers for each test
    readiness_name = :"readiness_drain_#{:erlang.unique_integer([:positive])}"
    drain_name = :"drain_#{:erlang.unique_integer([:positive])}"

    {:ok, _readiness_pid} = Readiness.start_link(name: readiness_name)

    {:ok, _drain_pid} =
      Drain.start_link(
        name: drain_name,
        readiness_server: readiness_name,
        drain_timeout: 1_000
      )

    %{drain_name: drain_name, readiness_name: readiness_name}
  end

  describe "draining?/1" do
    test "returns false when drain has not been initiated", %{drain_name: drain_name} do
      refute Drain.draining?(drain_name)
    end
  end

  describe "initiate/1" do
    test "executes drain and returns :ok", %{drain_name: drain_name} do
      assert :ok = Drain.initiate(drain_name)
    end

    test "marks readiness as not_ready during drain", %{
      drain_name: drain_name,
      readiness_name: readiness_name
    } do
      # Mark as ready first
      Readiness.report_ready(:endpoint, readiness_name)
      result = Readiness.check(readiness_name)
      assert result.status == :ready

      # Initiate drain
      assert :ok = Drain.initiate(drain_name)

      # After drain, readiness should show :drain as not_ready
      result = Readiness.check(readiness_name)
      assert result.subsystems[:drain] == false
    end

    test "is idempotent — calling initiate twice returns :ok both times", %{drain_name: drain_name} do
      assert :ok = Drain.initiate(drain_name)
      assert :ok = Drain.initiate(drain_name)
    end

    test "after drain completes, draining? returns false", %{drain_name: drain_name} do
      assert :ok = Drain.initiate(drain_name)
      refute Drain.draining?(drain_name)
    end
  end

  describe "drain steps execute in order" do
    test "all steps complete successfully", %{drain_name: drain_name, readiness_name: readiness_name} do
      # Register a subsystem as ready
      Readiness.report_ready(:endpoint, readiness_name)

      # Drain should complete all steps without error
      assert :ok = Drain.initiate(drain_name)

      # Verify the readiness was marked as not_ready (step 1)
      result = Readiness.check(readiness_name)
      assert result.subsystems[:drain] == false
    end
  end
end
