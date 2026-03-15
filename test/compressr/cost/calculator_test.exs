defmodule Compressr.Cost.CalculatorTest do
  use ExUnit.Case, async: true

  alias Compressr.Cost.{Calculator, Pricing, Tracker}

  setup do
    suffix = :erlang.unique_integer([:positive])
    pricing_name = :"pricing_calc_#{suffix}"
    tracker_name = :"tracker_calc_#{suffix}"

    {:ok, _} = Pricing.start_link(name: pricing_name)
    {:ok, _} = Tracker.start_link(name: tracker_name)

    %{pricing: pricing_name, tracker: tracker_name}
  end

  describe "calculate_cost/2" do
    test "returns zero breakdown for resource with no usage", ctx do
      result = Calculator.calculate_cost("no-usage", tracker: ctx.tracker, pricing: ctx.pricing)

      assert result == %{
               s3_storage: 0.0,
               s3_requests: 0.0,
               glacier_restore: 0.0,
               cross_az: 0.0,
               dynamodb: 0.0,
               total: 0.0
             }
    end

    test "calculates S3 PUT request costs", ctx do
      # Record 10,000 PUTs
      Tracker.record(:s3_put_count, "dest-1", 10_000, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("dest-1", tracker: ctx.tracker, pricing: ctx.pricing)

      # 10,000 PUTs / 1000 * $0.005 = $0.05
      assert result.s3_requests == 0.05
    end

    test "calculates S3 GET request costs", ctx do
      # Record 10,000 GETs
      Tracker.record(:s3_get_count, "dest-1", 10_000, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("dest-1", tracker: ctx.tracker, pricing: ctx.pricing)

      # 10,000 GETs / 1000 * $0.0004 = $0.004
      assert result.s3_requests == 0.004
    end

    test "calculates combined S3 request costs", ctx do
      Tracker.record(:s3_put_count, "dest-1", 10_000, ctx.tracker)
      Tracker.record(:s3_get_count, "dest-1", 10_000, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("dest-1", tracker: ctx.tracker, pricing: ctx.pricing)

      # PUTs: 10K/1K * 0.005 = 0.05; GETs: 10K/1K * 0.0004 = 0.004
      assert result.s3_requests == 0.054
    end

    test "calculates S3 storage costs", ctx do
      # Record 1 GB of bytes written
      one_gb = 1024 * 1024 * 1024
      Tracker.record(:s3_bytes_written, "dest-1", one_gb, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("dest-1", tracker: ctx.tracker, pricing: ctx.pricing)

      # 1 GB * $0.023/GB/month = $0.023
      assert result.s3_storage == 0.023
    end

    test "calculates cross-AZ transfer costs", ctx do
      # 10 GB of cross-AZ transfer
      ten_gb = 10 * 1024 * 1024 * 1024
      Tracker.record(:cross_az_bytes, "dest-1", ten_gb, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("dest-1", tracker: ctx.tracker, pricing: ctx.pricing)

      # 10 GB * $0.01/GB = $0.10
      assert_in_delta result.cross_az, 0.1, 0.001
    end

    test "calculates DynamoDB costs", ctx do
      # 1,000,000 RCUs and 500,000 WCUs
      Tracker.record(:dynamo_rcu, "table-1", 1_000_000, ctx.tracker)
      Tracker.record(:dynamo_wcu, "table-1", 500_000, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("table-1", tracker: ctx.tracker, pricing: ctx.pricing)

      # RCU: 1M * 0.00000025 = 0.25; WCU: 500K * 0.00000125 = 0.625
      assert_in_delta result.dynamodb, 0.875, 0.001
    end

    test "calculates Glacier restore costs", ctx do
      one_gb = 1024 * 1024 * 1024
      Tracker.record(:glacier_restore_bytes_bulk, "dest-1", one_gb, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("dest-1", tracker: ctx.tracker, pricing: ctx.pricing)

      # 1 GB * $0.0025/GB = $0.0025
      assert_in_delta result.glacier_restore, 0.0025, 0.0001
    end

    test "total equals sum of all categories", ctx do
      one_gb = 1024 * 1024 * 1024

      Tracker.record(:s3_bytes_written, "dest-1", one_gb, ctx.tracker)
      Tracker.record(:s3_put_count, "dest-1", 10_000, ctx.tracker)
      Tracker.record(:cross_az_bytes, "dest-1", one_gb, ctx.tracker)
      Tracker.record(:dynamo_rcu, "dest-1", 100_000, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_cost("dest-1", tracker: ctx.tracker, pricing: ctx.pricing)

      expected_total = result.s3_storage + result.s3_requests + result.glacier_restore +
                       result.cross_az + result.dynamodb

      assert_in_delta result.total, expected_total, 0.000001
    end
  end

  describe "calculate_total/1" do
    test "sums costs across all resources", ctx do
      Tracker.record(:s3_put_count, "dest-1", 10_000, ctx.tracker)
      Tracker.record(:s3_put_count, "dest-2", 10_000, ctx.tracker)
      :timer.sleep(10)

      result = Calculator.calculate_total(tracker: ctx.tracker, pricing: ctx.pricing)

      # Each dest: 10K/1K * 0.005 = 0.05; total = 0.10
      assert_in_delta result.s3_requests, 0.1, 0.001
      assert result.total > 0
    end

    test "returns zero breakdown when no usage", ctx do
      result = Calculator.calculate_total(tracker: ctx.tracker, pricing: ctx.pricing)

      assert result == %{
               s3_storage: 0.0,
               s3_requests: 0.0,
               glacier_restore: 0.0,
               cross_az: 0.0,
               dynamodb: 0.0,
               total: 0.0
             }
    end
  end

  describe "estimate_glacier_restore/3" do
    test "calculates bulk tier cost", ctx do
      one_gb = 1024 * 1024 * 1024
      result = Calculator.estimate_glacier_restore(one_gb, :bulk, pricing: ctx.pricing)

      # 1 GB * $0.0025 = $0.0025
      assert_in_delta result, 0.0025, 0.0001
    end

    test "calculates standard tier cost", ctx do
      one_gb = 1024 * 1024 * 1024
      result = Calculator.estimate_glacier_restore(one_gb, :standard, pricing: ctx.pricing)

      assert_in_delta result, 0.01, 0.001
    end

    test "calculates expedited tier cost", ctx do
      one_gb = 1024 * 1024 * 1024
      result = Calculator.estimate_glacier_restore(one_gb, :expedited, pricing: ctx.pricing)

      assert_in_delta result, 0.03, 0.001
    end

    test "returns error for unknown tier", ctx do
      result = Calculator.estimate_glacier_restore(1024, :nonexistent, pricing: ctx.pricing)
      assert result == {:error, :unknown_tier}
    end
  end

  describe "estimate_monthly/2" do
    test "returns zero breakdown for resource with no usage", ctx do
      result = Calculator.estimate_monthly("no-usage", tracker: ctx.tracker, pricing: ctx.pricing)

      assert result.total == 0.0
    end

    test "projects monthly cost from current rate", ctx do
      Tracker.record(:s3_put_count, "dest-1", 10_000, ctx.tracker)
      :timer.sleep(10)

      now = DateTime.utc_now()
      # Simulate 1 day of data
      period_start = DateTime.add(now, -86_400, :second)

      result = Calculator.estimate_monthly("dest-1",
        tracker: ctx.tracker,
        pricing: ctx.pricing,
        now: now,
        period_start: period_start
      )

      # Daily cost: 10K/1K * 0.005 = 0.05; monthly: 0.05 * 30 = 1.5
      assert_in_delta result.s3_requests, 1.5, 0.1
      assert result.total > 0
    end
  end
end
