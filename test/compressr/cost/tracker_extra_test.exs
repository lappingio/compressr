defmodule Compressr.Cost.TrackerExtraTest do
  use ExUnit.Case, async: true

  alias Compressr.Cost.Tracker

  setup do
    name = :"tracker_extra_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Tracker.start_link(name: name)
    %{tracker: name}
  end

  describe "scheduled_reset" do
    test "handles :scheduled_reset message", %{tracker: tracker} do
      # Record some data
      Tracker.record(:s3_put_count, "dest-1", 100, tracker)
      :timer.sleep(10)
      assert Tracker.get_usage("dest-1", tracker)[:s3_put_count] == 100

      # Simulate scheduled reset
      send(Process.whereis(tracker), :scheduled_reset)
      :timer.sleep(10)

      assert Tracker.get_all_usage(tracker) == %{}
    end
  end

  describe "multiple metrics on same resource" do
    test "tracks multiple metrics independently", %{tracker: tracker} do
      Tracker.record(:s3_put_count, "dest-1", 10, tracker)
      Tracker.record(:s3_bytes_written, "dest-1", 1024, tracker)
      Tracker.record(:s3_get_count, "dest-1", 5, tracker)
      Tracker.record(:dynamo_rcu, "dest-1", 50, tracker)
      Tracker.record(:dynamo_wcu, "dest-1", 25, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:s3_put_count] == 10
      assert usage[:s3_bytes_written] == 1024
      assert usage[:s3_get_count] == 5
      assert usage[:dynamo_rcu] == 50
      assert usage[:dynamo_wcu] == 25
    end
  end

  describe "reset/1" do
    test "reset returns :ok", %{tracker: tracker} do
      assert :ok = Tracker.reset(tracker)
    end

    test "multiple resets are idempotent", %{tracker: tracker} do
      Tracker.record(:s3_put_count, "dest-1", 10, tracker)
      :timer.sleep(10)

      :ok = Tracker.reset(tracker)
      :ok = Tracker.reset(tracker)

      assert Tracker.get_all_usage(tracker) == %{}
    end
  end

  describe "start_link with different reset intervals" do
    test "starts with :daily reset interval" do
      name = :"tracker_daily_x_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Tracker.start_link(name: name, reset_interval: :daily)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with custom (unsupported) reset interval" do
      name = :"tracker_custom_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Tracker.start_link(name: name, reset_interval: :never)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end

  describe "default name functions" do
    test "record and get_usage work with default name" do
      case Tracker.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      Tracker.record(:s3_put_count, "default-test", 1)
      :timer.sleep(10)
      usage = Tracker.get_usage("default-test")
      assert usage[:s3_put_count] >= 1

      # get_all_usage with default name
      all = Tracker.get_all_usage()
      assert is_map(all)

      # reset with default name
      :ok = Tracker.reset()
    end
  end

  describe "large values" do
    test "handles large byte counts", %{tracker: tracker} do
      large_value = 1_099_511_627_776  # 1 TB
      Tracker.record(:s3_bytes_written, "dest-1", large_value, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:s3_bytes_written] == large_value
    end

    test "handles float amounts", %{tracker: tracker} do
      Tracker.record(:s3_bytes_written, "dest-1", 1.5, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:s3_bytes_written] == 1.5
    end
  end
end
