defmodule Compressr.Schema.Registry.VolumeTrackerTest do
  use ExUnit.Case, async: true

  alias Compressr.Schema.Registry.VolumeTracker

  setup do
    {:ok, pid} = VolumeTracker.start_link(name: nil, window_seconds: 60)
    %{tracker: pid}
  end

  describe "record/4 and get_breakdown/2" do
    test "records events and returns breakdown", %{tracker: tracker} do
      VolumeTracker.record(tracker, "source-1", "http_access", 100)
      VolumeTracker.record(tracker, "source-1", "http_access", 150)
      VolumeTracker.record(tracker, "source-1", "syslog", 80)

      # Allow casts to process
      :timer.sleep(10)

      breakdown = VolumeTracker.get_breakdown(tracker, "source-1")

      assert Map.has_key?(breakdown, "http_access")
      assert Map.has_key?(breakdown, "syslog")

      # http_access: 2 events, syslog: 1 event
      assert breakdown["http_access"].events_per_sec > 0
      assert breakdown["syslog"].events_per_sec > 0
      assert breakdown["http_access"].bytes_per_sec > 0
      assert breakdown["syslog"].bytes_per_sec > 0
    end

    test "tracks multiple log types independently", %{tracker: tracker} do
      for _ <- 1..10 do
        VolumeTracker.record(tracker, "source-1", "http_access", 100)
      end

      for _ <- 1..5 do
        VolumeTracker.record(tracker, "source-1", "syslog", 80)
      end

      :timer.sleep(10)

      breakdown = VolumeTracker.get_breakdown(tracker, "source-1")

      # http_access should have more events than syslog
      assert breakdown["http_access"].events_per_sec > breakdown["syslog"].events_per_sec
    end

    test "calculates percentages correctly", %{tracker: tracker} do
      for _ <- 1..6 do
        VolumeTracker.record(tracker, "source-1", "http_access", 100)
      end

      for _ <- 1..4 do
        VolumeTracker.record(tracker, "source-1", "syslog", 80)
      end

      :timer.sleep(10)

      breakdown = VolumeTracker.get_breakdown(tracker, "source-1")

      assert breakdown["http_access"].percentage == 60.0
      assert breakdown["syslog"].percentage == 40.0
    end

    test "sources are isolated", %{tracker: tracker} do
      VolumeTracker.record(tracker, "source-1", "http_access", 100)
      VolumeTracker.record(tracker, "source-2", "syslog", 80)

      :timer.sleep(10)

      breakdown1 = VolumeTracker.get_breakdown(tracker, "source-1")
      breakdown2 = VolumeTracker.get_breakdown(tracker, "source-2")

      assert Map.has_key?(breakdown1, "http_access")
      refute Map.has_key?(breakdown1, "syslog")

      assert Map.has_key?(breakdown2, "syslog")
      refute Map.has_key?(breakdown2, "http_access")
    end

    test "returns empty map for unknown source", %{tracker: tracker} do
      breakdown = VolumeTracker.get_breakdown(tracker, "unknown")
      assert breakdown == %{}
    end
  end

  describe "default name functions" do
    test "record and get_breakdown work with default module name" do
      case VolumeTracker.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      VolumeTracker.record("def-src", "def-type", 100)
      :timer.sleep(10)
      breakdown = VolumeTracker.get_breakdown("def-src")
      assert is_map(breakdown)
    end
  end

  describe "window pruning" do
    test "entries outside window are pruned" do
      {:ok, pid} = VolumeTracker.start_link(name: nil, window_seconds: 1)

      VolumeTracker.record(pid, "src-prune", "type-1", 100)
      :timer.sleep(10)

      # Should have data immediately
      breakdown = VolumeTracker.get_breakdown(pid, "src-prune")
      assert Map.has_key?(breakdown, "type-1")
      assert breakdown["type-1"].events_per_sec > 0

      # Wait for entries to expire
      :timer.sleep(1200)

      breakdown = VolumeTracker.get_breakdown(pid, "src-prune")
      if Map.has_key?(breakdown, "type-1") do
        assert breakdown["type-1"].percentage == 0.0
      end

      GenServer.stop(pid)
    end
  end
end
