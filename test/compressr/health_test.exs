defmodule Compressr.HealthTest do
  use ExUnit.Case, async: true

  alias Compressr.Health

  describe "check/0" do
    test "returns a map with expected keys" do
      result = Health.check()

      assert is_map(result)
      assert Map.has_key?(result, :status)
      assert Map.has_key?(result, :node)
      assert Map.has_key?(result, :uptime_seconds)
      assert Map.has_key?(result, :memory)
      assert Map.has_key?(result, :peers)
      assert Map.has_key?(result, :peer_count)
    end

    test "returns :ok status under normal conditions" do
      result = Health.check()
      assert result.status == :ok
    end

    test "returns the current node name" do
      result = Health.check()
      assert result.node == node()
    end

    test "returns uptime as a non-negative integer" do
      result = Health.check()
      assert is_integer(result.uptime_seconds)
      assert result.uptime_seconds >= 0
    end

    test "returns memory with total and used keys" do
      result = Health.check()
      assert is_integer(result.memory.total)
      assert is_integer(result.memory.used)
      assert result.memory.total > 0
      assert result.memory.used > 0
    end

    test "returns peers as a list" do
      result = Health.check()
      assert is_list(result.peers)
    end

    test "returns peer_count as a non-negative integer" do
      result = Health.check()
      assert is_integer(result.peer_count)
      assert result.peer_count >= 0
      assert result.peer_count == length(result.peers)
    end
  end
end
