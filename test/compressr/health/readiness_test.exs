defmodule Compressr.Health.ReadinessTest do
  use ExUnit.Case, async: true

  alias Compressr.Health.Readiness

  setup do
    name = :"readiness_#{:erlang.unique_integer([:positive])}"
    {:ok, pid} = Readiness.start_link(name: name)
    %{pid: pid, name: name}
  end

  describe "check/1" do
    test "returns not_ready when no subsystems are registered", %{name: name} do
      result = Readiness.check(name)
      assert result.status == :not_ready
      assert result.subsystems == %{}
    end
  end

  describe "report_ready/2" do
    test "marks a subsystem as ready", %{name: name} do
      :ok = Readiness.report_ready(:endpoint, name)

      result = Readiness.check(name)
      assert result.status == :ready
      assert result.subsystems == %{endpoint: true}
    end

    test "returns ready when all subsystems are ready", %{name: name} do
      :ok = Readiness.report_ready(:endpoint, name)
      :ok = Readiness.report_ready(:database, name)

      result = Readiness.check(name)
      assert result.status == :ready
      assert result.subsystems == %{endpoint: true, database: true}
    end
  end

  describe "report_not_ready/2" do
    test "marks a subsystem as not ready", %{name: name} do
      :ok = Readiness.report_ready(:endpoint, name)
      :ok = Readiness.report_not_ready(:endpoint, name)

      result = Readiness.check(name)
      assert result.status == :not_ready
      assert result.subsystems == %{endpoint: false}
    end

    test "returns not_ready when any subsystem is not ready", %{name: name} do
      :ok = Readiness.report_ready(:endpoint, name)
      :ok = Readiness.report_not_ready(:database, name)

      result = Readiness.check(name)
      assert result.status == :not_ready
      assert result.subsystems == %{endpoint: true, database: false}
    end
  end
end
