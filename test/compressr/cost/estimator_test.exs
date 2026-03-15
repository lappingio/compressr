defmodule Compressr.Cost.EstimatorTest do
  use ExUnit.Case, async: true

  alias Compressr.Cost.{Estimator, Pricing}

  setup do
    name = :"pricing_est_#{:erlang.unique_integer([:positive])}"
    {:ok, _} = Pricing.start_link(name: name)
    %{pricing: name}
  end

  describe "estimate_glacier_replay/3" do
    test "returns all three retrieval tiers", ctx do
      result = Estimator.estimate_glacier_replay(1000, 10_737_418_240, pricing: ctx.pricing)

      assert length(result) == 3
      tiers = Enum.map(result, & &1.tier)
      assert :bulk in tiers
      assert :standard in tiers
      assert :expedited in tiers
    end

    test "bulk is cheapest, expedited is most expensive", ctx do
      result = Estimator.estimate_glacier_replay(1000, 10_737_418_240, pricing: ctx.pricing)

      costs = Enum.map(result, & &1.cost)
      [bulk_cost, standard_cost, expedited_cost] = costs

      assert bulk_cost < standard_cost
      assert standard_cost < expedited_cost
    end

    test "calculates correct costs for 10 GB", ctx do
      ten_gb = 10 * 1024 * 1024 * 1024
      result = Estimator.estimate_glacier_replay(1000, ten_gb, pricing: ctx.pricing)

      bulk = Enum.find(result, &(&1.tier == :bulk))
      standard = Enum.find(result, &(&1.tier == :standard))
      expedited = Enum.find(result, &(&1.tier == :expedited))

      # 10 GB * $0.0025/GB = $0.025
      assert_in_delta bulk.cost, 0.025, 0.001
      # 10 GB * $0.01/GB = $0.10
      assert_in_delta standard.cost, 0.1, 0.001
      # 10 GB * $0.03/GB = $0.30
      assert_in_delta expedited.cost, 0.3, 0.001
    end

    test "includes per_gb rate for each tier", ctx do
      result = Estimator.estimate_glacier_replay(100, 1_073_741_824, pricing: ctx.pricing)

      bulk = Enum.find(result, &(&1.tier == :bulk))
      assert bulk.per_gb == 0.0025

      standard = Enum.find(result, &(&1.tier == :standard))
      assert standard.per_gb == 0.01

      expedited = Enum.find(result, &(&1.tier == :expedited))
      assert expedited.per_gb == 0.03
    end

    test "includes time estimate for each tier", ctx do
      result = Estimator.estimate_glacier_replay(100, 1_073_741_824, pricing: ctx.pricing)

      Enum.each(result, fn tier ->
        assert is_binary(tier.time_hours)
        assert String.length(tier.time_hours) > 0
      end)
    end

    test "handles zero bytes", ctx do
      result = Estimator.estimate_glacier_replay(0, 0, pricing: ctx.pricing)

      Enum.each(result, fn tier ->
        assert tier.cost == 0.0
      end)
    end

    test "handles very large restores (1 TB)", ctx do
      one_tb = 1024 * 1024 * 1024 * 1024
      result = Estimator.estimate_glacier_replay(100_000, one_tb, pricing: ctx.pricing)

      bulk = Enum.find(result, &(&1.tier == :bulk))
      # 1024 GB * $0.0025 = $2.56
      assert_in_delta bulk.cost, 2.56, 0.01

      expedited = Enum.find(result, &(&1.tier == :expedited))
      # 1024 GB * $0.03 = $30.72
      assert_in_delta expedited.cost, 30.72, 0.01
    end
  end

  describe "estimate_athena_query/2" do
    test "calculates cost for 1 TB scan", ctx do
      one_tb = 1024 * 1024 * 1024 * 1024
      result = Estimator.estimate_athena_query(one_tb, pricing: ctx.pricing)

      assert result.bytes_scanned == one_tb
      assert_in_delta result.tb_scanned, 1.0, 0.001
      assert_in_delta result.estimated_cost, 5.0, 0.001
    end

    test "calculates cost for 100 GB scan", ctx do
      hundred_gb = 100 * 1024 * 1024 * 1024
      result = Estimator.estimate_athena_query(hundred_gb, pricing: ctx.pricing)

      # 100 GB = ~0.0977 TB; cost = 0.0977 * $5 = ~$0.4883
      assert_in_delta result.tb_scanned, 0.0977, 0.001
      assert_in_delta result.estimated_cost, 0.4883, 0.01
    end

    test "handles zero bytes scanned", ctx do
      result = Estimator.estimate_athena_query(0, pricing: ctx.pricing)

      assert result.bytes_scanned == 0
      assert result.tb_scanned == 0.0
      assert result.estimated_cost == 0.0
    end

    test "handles very large scans (10 TB)", ctx do
      ten_tb = 10 * 1024 * 1024 * 1024 * 1024
      result = Estimator.estimate_athena_query(ten_tb, pricing: ctx.pricing)

      assert_in_delta result.tb_scanned, 10.0, 0.001
      assert_in_delta result.estimated_cost, 50.0, 0.01
    end

    test "returns bytes_scanned in result", ctx do
      bytes = 5_000_000_000
      result = Estimator.estimate_athena_query(bytes, pricing: ctx.pricing)

      assert result.bytes_scanned == bytes
    end

    test "uses configurable pricing", ctx do
      # Update Athena pricing
      Pricing.update_price(:athena, :per_tb_scanned, 10.0, ctx.pricing)

      one_tb = 1024 * 1024 * 1024 * 1024
      result = Estimator.estimate_athena_query(one_tb, pricing: ctx.pricing)

      assert_in_delta result.estimated_cost, 10.0, 0.001
    end
  end
end
