defmodule Compressr.Cost.EstimatorExtraTest do
  use ExUnit.Case, async: true

  alias Compressr.Cost.{Estimator, Pricing}

  setup do
    name = :"pricing_est_extra_#{:erlang.unique_integer([:positive])}"
    {:ok, _} = Pricing.start_link(name: name)
    %{pricing: name}
  end

  describe "estimate_glacier_replay/3 edge cases" do
    test "handles fractional GB values", ctx do
      # 500 MB = 0.5 GB
      half_gb = 500 * 1024 * 1024
      result = Estimator.estimate_glacier_replay(100, half_gb, pricing: ctx.pricing)

      bulk = Enum.find(result, &(&1.tier == :bulk))
      # 0.465 GB * 0.0025 = ~0.001164 (approximately, due to 500MB = ~0.4657 GB)
      assert bulk.cost > 0
      assert bulk.cost < 0.01
    end

    test "each tier has time_hours field", ctx do
      result = Estimator.estimate_glacier_replay(1, 1024, pricing: ctx.pricing)

      Enum.each(result, fn tier ->
        assert Map.has_key?(tier, :time_hours)
        assert is_binary(tier.time_hours)
      end)
    end

    test "each tier has per_gb field with correct rate", ctx do
      result = Estimator.estimate_glacier_replay(1, 1024, pricing: ctx.pricing)

      bulk = Enum.find(result, &(&1.tier == :bulk))
      assert bulk.per_gb == 0.0025

      standard = Enum.find(result, &(&1.tier == :standard))
      assert standard.per_gb == 0.01

      expedited = Enum.find(result, &(&1.tier == :expedited))
      assert expedited.per_gb == 0.03
    end

    test "handles custom pricing", ctx do
      Pricing.update_price(:glacier_restore, :bulk, 0.005, ctx.pricing)

      one_gb = 1024 * 1024 * 1024
      result = Estimator.estimate_glacier_replay(1, one_gb, pricing: ctx.pricing)

      bulk = Enum.find(result, &(&1.tier == :bulk))
      assert_in_delta bulk.cost, 0.005, 0.001
    end

    test "always returns exactly 3 tiers", ctx do
      for bytes <- [0, 1024, 1_073_741_824, 10_737_418_240] do
        result = Estimator.estimate_glacier_replay(1, bytes, pricing: ctx.pricing)
        assert length(result) == 3
      end
    end
  end

  describe "estimate_athena_query/2 edge cases" do
    test "handles 1 byte scan", ctx do
      result = Estimator.estimate_athena_query(1, pricing: ctx.pricing)

      assert result.bytes_scanned == 1
      assert result.tb_scanned >= 0
      assert result.estimated_cost >= 0
      assert result.estimated_cost < 0.001
    end

    test "handles custom athena pricing", ctx do
      Pricing.update_price(:athena, :per_tb_scanned, 0.0, ctx.pricing)

      one_tb = 1024 * 1024 * 1024 * 1024
      result = Estimator.estimate_athena_query(one_tb, pricing: ctx.pricing)

      assert result.estimated_cost == 0.0
    end

    test "result contains all expected keys", ctx do
      result = Estimator.estimate_athena_query(1000, pricing: ctx.pricing)

      assert Map.has_key?(result, :bytes_scanned)
      assert Map.has_key?(result, :tb_scanned)
      assert Map.has_key?(result, :estimated_cost)
    end

    test "handles 100 TB scan", ctx do
      hundred_tb = 100 * 1024 * 1024 * 1024 * 1024
      result = Estimator.estimate_athena_query(hundred_tb, pricing: ctx.pricing)

      assert_in_delta result.tb_scanned, 100.0, 0.001
      assert_in_delta result.estimated_cost, 500.0, 0.01
    end
  end

  describe "pricing error handling" do
    test "glacier replay handles unknown pricing service gracefully" do
      # Start a pricing agent with empty pricing
      name = :"empty_pricing_#{:erlang.unique_integer([:positive])}"
      Agent.start_link(fn -> %{} end, name: name)

      result = Estimator.estimate_glacier_replay(1, 1_073_741_824, pricing: name)

      # Should return 0.0 cost for each tier since pricing returns error
      Enum.each(result, fn tier ->
        assert tier.cost == 0.0
      end)

      Agent.stop(name)
    end

    test "athena query handles unknown pricing service gracefully" do
      name = :"empty_pricing2_#{:erlang.unique_integer([:positive])}"
      Agent.start_link(fn -> %{} end, name: name)

      result = Estimator.estimate_athena_query(1_099_511_627_776, pricing: name)
      assert result.estimated_cost == 0.0

      Agent.stop(name)
    end
  end
end
