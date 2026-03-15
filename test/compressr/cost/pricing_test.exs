defmodule Compressr.Cost.PricingTest do
  use ExUnit.Case, async: true

  alias Compressr.Cost.Pricing

  setup do
    name = :"pricing_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Pricing.start_link(name: name)
    %{pricing: name}
  end

  describe "start_link/1" do
    test "starts with default pricing", %{pricing: pricing} do
      all = Pricing.get_all(pricing)
      assert is_map(all)
      assert Map.has_key?(all, :s3_storage)
      assert Map.has_key?(all, :s3_put)
      assert Map.has_key?(all, :s3_get)
      assert Map.has_key?(all, :glacier_restore)
      assert Map.has_key?(all, :cross_az_transfer)
      assert Map.has_key?(all, :dynamodb)
      assert Map.has_key?(all, :athena)
    end
  end

  describe "get_price/3" do
    test "returns S3 PUT price for standard class", %{pricing: pricing} do
      assert Pricing.get_price(:s3_put, :standard, pricing) == 0.005
    end

    test "returns S3 GET price for standard class", %{pricing: pricing} do
      assert Pricing.get_price(:s3_get, :standard, pricing) == 0.0004
    end

    test "returns S3 storage price for standard class", %{pricing: pricing} do
      assert Pricing.get_price(:s3_storage, :standard, pricing) == 0.023
    end

    test "returns S3 storage price for Glacier Deep Archive", %{pricing: pricing} do
      assert Pricing.get_price(:s3_storage, :glacier_deep_archive, pricing) == 0.00099
    end

    test "returns Glacier restore price for bulk tier", %{pricing: pricing} do
      assert Pricing.get_price(:glacier_restore, :bulk, pricing) == 0.0025
    end

    test "returns Glacier restore price for standard tier", %{pricing: pricing} do
      assert Pricing.get_price(:glacier_restore, :standard, pricing) == 0.01
    end

    test "returns Glacier restore price for expedited tier", %{pricing: pricing} do
      assert Pricing.get_price(:glacier_restore, :expedited, pricing) == 0.03
    end

    test "returns cross-AZ transfer price", %{pricing: pricing} do
      assert Pricing.get_price(:cross_az_transfer, :per_gb, pricing) == 0.01
    end

    test "returns DynamoDB RCU price", %{pricing: pricing} do
      assert Pricing.get_price(:dynamodb, :per_rcu, pricing) == 0.00000025
    end

    test "returns DynamoDB WCU price", %{pricing: pricing} do
      assert Pricing.get_price(:dynamodb, :per_wcu, pricing) == 0.00000125
    end

    test "returns Athena per TB scanned price", %{pricing: pricing} do
      assert Pricing.get_price(:athena, :per_tb_scanned, pricing) == 5.0
    end

    test "returns error for unknown service", %{pricing: pricing} do
      assert Pricing.get_price(:nonexistent, :foo, pricing) == {:error, :unknown_service}
    end

    test "returns error for unknown tier", %{pricing: pricing} do
      assert Pricing.get_price(:s3_storage, :nonexistent, pricing) == {:error, :unknown_tier}
    end
  end

  describe "get_service_pricing/2" do
    test "returns all tiers for S3 storage", %{pricing: pricing} do
      result = Pricing.get_service_pricing(:s3_storage, pricing)
      assert is_map(result)
      assert Map.has_key?(result, :standard)
      assert Map.has_key?(result, :glacier_deep_archive)
    end

    test "returns error for unknown service", %{pricing: pricing} do
      assert Pricing.get_service_pricing(:nonexistent, pricing) == {:error, :unknown_service}
    end
  end

  describe "update_price/4" do
    test "updates a price at runtime", %{pricing: pricing} do
      assert Pricing.get_price(:s3_storage, :standard, pricing) == 0.023

      :ok = Pricing.update_price(:s3_storage, :standard, 0.05, pricing)

      assert Pricing.get_price(:s3_storage, :standard, pricing) == 0.05
    end

    test "does not affect other tiers when updating one", %{pricing: pricing} do
      original_ia = Pricing.get_price(:s3_storage, :standard_ia, pricing)

      :ok = Pricing.update_price(:s3_storage, :standard, 0.99, pricing)

      assert Pricing.get_price(:s3_storage, :standard_ia, pricing) == original_ia
    end

    test "can add new tiers to existing service", %{pricing: pricing} do
      :ok = Pricing.update_price(:s3_storage, :custom_tier, 0.042, pricing)

      assert Pricing.get_price(:s3_storage, :custom_tier, pricing) == 0.042
    end
  end

  describe "default_pricing/0" do
    test "returns the default pricing map" do
      defaults = Pricing.default_pricing()
      assert is_map(defaults)
      assert defaults.s3_storage.standard == 0.023
    end
  end

  describe "config override" do
    test "merges application config with defaults" do
      # Store original config
      original = Application.get_env(:compressr, Pricing)

      try do
        Application.put_env(:compressr, Pricing, %{
          s3_storage: %{standard: 0.999}
        })

        name = :"pricing_config_test_#{:erlang.unique_integer([:positive])}"
        {:ok, _pid} = Pricing.start_link(name: name)

        # The overridden value should be in place
        assert Pricing.get_price(:s3_storage, :standard, name) == 0.999
      after
        if original do
          Application.put_env(:compressr, Pricing, original)
        else
          Application.delete_env(:compressr, Pricing)
        end
      end
    end
  end
end
