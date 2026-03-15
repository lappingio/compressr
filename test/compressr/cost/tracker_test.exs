defmodule Compressr.Cost.TrackerTest do
  use ExUnit.Case, async: true

  alias Compressr.Cost.Tracker

  setup do
    name = :"tracker_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Tracker.start_link(name: name)
    %{tracker: name}
  end

  describe "record/4 and get_usage/2" do
    test "records and retrieves s3_put_count", %{tracker: tracker} do
      Tracker.record(:s3_put_count, "dest-1", 1, tracker)
      # Give the cast time to process
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:s3_put_count] == 1
    end

    test "increments counters on subsequent records", %{tracker: tracker} do
      Tracker.record(:s3_put_count, "dest-1", 5, tracker)
      Tracker.record(:s3_put_count, "dest-1", 3, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:s3_put_count] == 8
    end

    test "records s3_bytes_written", %{tracker: tracker} do
      Tracker.record(:s3_bytes_written, "dest-1", 1024, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:s3_bytes_written] == 1024
    end

    test "records s3_get_count", %{tracker: tracker} do
      Tracker.record(:s3_get_count, "dest-1", 10, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:s3_get_count] == 10
    end

    test "records glacier_restore_bytes per tier", %{tracker: tracker} do
      Tracker.record(:glacier_restore_bytes_bulk, "dest-1", 5000, tracker)
      Tracker.record(:glacier_restore_bytes_standard, "dest-1", 3000, tracker)
      Tracker.record(:glacier_restore_bytes_expedited, "dest-1", 1000, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:glacier_restore_bytes_bulk] == 5000
      assert usage[:glacier_restore_bytes_standard] == 3000
      assert usage[:glacier_restore_bytes_expedited] == 1000
    end

    test "records cross_az_bytes", %{tracker: tracker} do
      Tracker.record(:cross_az_bytes, "dest-1", 2048, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("dest-1", tracker)
      assert usage[:cross_az_bytes] == 2048
    end

    test "records dynamo_rcu and dynamo_wcu", %{tracker: tracker} do
      Tracker.record(:dynamo_rcu, "table-1", 100, tracker)
      Tracker.record(:dynamo_wcu, "table-1", 50, tracker)
      :timer.sleep(10)

      usage = Tracker.get_usage("table-1", tracker)
      assert usage[:dynamo_rcu] == 100
      assert usage[:dynamo_wcu] == 50
    end
  end

  describe "multiple resources tracked independently" do
    test "different resources have independent counters", %{tracker: tracker} do
      Tracker.record(:s3_put_count, "dest-1", 10, tracker)
      Tracker.record(:s3_put_count, "dest-2", 20, tracker)
      :timer.sleep(10)

      assert Tracker.get_usage("dest-1", tracker)[:s3_put_count] == 10
      assert Tracker.get_usage("dest-2", tracker)[:s3_put_count] == 20
    end

    test "returns empty map for unknown resource", %{tracker: tracker} do
      assert Tracker.get_usage("nonexistent", tracker) == %{}
    end
  end

  describe "get_all_usage/1" do
    test "returns all resources and their counters", %{tracker: tracker} do
      Tracker.record(:s3_put_count, "dest-1", 5, tracker)
      Tracker.record(:s3_get_count, "dest-2", 10, tracker)
      :timer.sleep(10)

      all = Tracker.get_all_usage(tracker)
      assert map_size(all) == 2
      assert all["dest-1"][:s3_put_count] == 5
      assert all["dest-2"][:s3_get_count] == 10
    end

    test "returns empty map when no usage recorded", %{tracker: tracker} do
      assert Tracker.get_all_usage(tracker) == %{}
    end
  end

  describe "reset/1" do
    test "clears all counters", %{tracker: tracker} do
      Tracker.record(:s3_put_count, "dest-1", 100, tracker)
      :timer.sleep(10)

      assert Tracker.get_usage("dest-1", tracker)[:s3_put_count] == 100

      :ok = Tracker.reset(tracker)

      assert Tracker.get_all_usage(tracker) == %{}
      assert Tracker.get_usage("dest-1", tracker) == %{}
    end
  end

  describe "valid_metrics/0" do
    test "returns a list of valid metric atoms" do
      metrics = Tracker.valid_metrics()
      assert is_list(metrics)
      assert :s3_put_count in metrics
      assert :s3_get_count in metrics
      assert :s3_bytes_written in metrics
      assert :glacier_restore_bytes_bulk in metrics
      assert :glacier_restore_bytes_standard in metrics
      assert :glacier_restore_bytes_expedited in metrics
      assert :cross_az_bytes in metrics
      assert :dynamo_rcu in metrics
      assert :dynamo_wcu in metrics
    end
  end

  describe "start_link/1 options" do
    test "accepts custom reset_interval" do
      name = :"tracker_daily_#{:erlang.unique_integer([:positive])}"
      {:ok, pid} = Tracker.start_link(name: name, reset_interval: :daily)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end
  end
end
