defmodule Compressr.Destination.Iceberg.PartitionTest do
  use ExUnit.Case, async: true

  alias Compressr.Destination.Iceberg.Partition

  describe "partition_value/2 with :daily" do
    test "extracts date string from event timestamp" do
      # 2026-03-15 10:30:00 UTC
      event = %{"_time" => 1_773_570_600}
      assert Partition.partition_value(event, :daily) == "2026-03-15"
    end

    test "handles midnight correctly" do
      # 2026-03-15 00:00:00 UTC
      event = %{"_time" => 1_773_532_800}
      assert Partition.partition_value(event, :daily) == "2026-03-15"
    end

    test "handles end of day correctly" do
      # 2026-03-15 23:59:59 UTC
      event = %{"_time" => 1_773_619_199}
      assert Partition.partition_value(event, :daily) == "2026-03-15"
    end

    test "handles year boundary" do
      # 2025-12-31 23:59:59 UTC
      event = %{"_time" => 1_767_225_599}
      assert Partition.partition_value(event, :daily) == "2025-12-31"
    end

    test "handles new year" do
      # 2026-01-01 00:00:00 UTC
      event = %{"_time" => 1_767_225_600}
      assert Partition.partition_value(event, :daily) == "2026-01-01"
    end

    test "defaults to epoch when _time is missing" do
      event = %{}
      assert Partition.partition_value(event, :daily) == "1970-01-01"
    end
  end

  describe "partition_value/2 with :hourly" do
    test "extracts date and hour from event timestamp" do
      # 2026-03-15 14:30:00 UTC
      event = %{"_time" => 1_773_585_000}
      assert Partition.partition_value(event, :hourly) == "2026-03-15-14"
    end

    test "handles midnight hour correctly" do
      # 2026-03-15 00:00:00 UTC
      event = %{"_time" => 1_773_532_800}
      assert Partition.partition_value(event, :hourly) == "2026-03-15-00"
    end

    test "handles hour 23 correctly" do
      # 2026-03-15 23:30:00 UTC
      event = %{"_time" => 1_773_617_400}
      assert Partition.partition_value(event, :hourly) == "2026-03-15-23"
    end

    test "handles year boundary at midnight" do
      # 2026-01-01 00:00:00 UTC
      event = %{"_time" => 1_767_225_600}
      assert Partition.partition_value(event, :hourly) == "2026-01-01-00"
    end
  end

  describe "partition_path/1" do
    test "wraps value in dt= prefix" do
      assert Partition.partition_path("2026-03-15") == "dt=2026-03-15"
    end

    test "works with hourly values" do
      assert Partition.partition_path("2026-03-15-14") == "dt=2026-03-15-14"
    end
  end

  describe "data_prefix/4" do
    test "builds full Iceberg-style data path" do
      result = Partition.data_prefix("warehouse", "mydb", "events", "2026-03-15")
      assert result == "warehouse/mydb/events/data/dt=2026-03-15"
    end

    test "builds path with hourly partition" do
      result = Partition.data_prefix("warehouse", "mydb", "events", "2026-03-15-14")
      assert result == "warehouse/mydb/events/data/dt=2026-03-15-14"
    end
  end
end
