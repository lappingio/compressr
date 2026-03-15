defmodule Compressr.Cost.PricingExtraTest do
  use ExUnit.Case, async: true

  alias Compressr.Cost.Pricing

  setup do
    name = :"pricing_extra_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Pricing.start_link(name: name)
    %{pricing: name}
  end

  describe "get_price/3 edge cases" do
    test "returns all S3 storage tiers", %{pricing: pricing} do
      tiers = [:standard, :intelligent_tiering, :standard_ia, :one_zone_ia,
               :glacier_instant, :glacier_flexible, :glacier_deep_archive]

      Enum.each(tiers, fn tier ->
        price = Pricing.get_price(:s3_storage, tier, pricing)
        assert is_number(price), "Expected number for tier #{tier}, got #{inspect(price)}"
        assert price > 0
      end)
    end

    test "returns all S3 PUT tiers", %{pricing: pricing} do
      tiers = [:standard, :intelligent_tiering, :standard_ia, :one_zone_ia,
               :glacier_instant, :glacier_flexible, :glacier_deep_archive]

      Enum.each(tiers, fn tier ->
        price = Pricing.get_price(:s3_put, tier, pricing)
        assert is_number(price)
      end)
    end

    test "returns all S3 GET tiers", %{pricing: pricing} do
      tiers = [:standard, :intelligent_tiering, :standard_ia, :one_zone_ia,
               :glacier_instant, :glacier_flexible, :glacier_deep_archive]

      Enum.each(tiers, fn tier ->
        price = Pricing.get_price(:s3_get, tier, pricing)
        assert is_number(price)
      end)
    end

    test "returns all glacier restore tiers", %{pricing: pricing} do
      for tier <- [:bulk, :standard, :expedited] do
        price = Pricing.get_price(:glacier_restore, tier, pricing)
        assert is_number(price)
      end
    end
  end

  describe "update_price/4 edge cases" do
    test "creates new service when it doesn't exist", %{pricing: pricing} do
      :ok = Pricing.update_price(:custom_service, :tier1, 0.123, pricing)
      assert Pricing.get_price(:custom_service, :tier1, pricing) == 0.123
    end

    test "can set price to zero", %{pricing: pricing} do
      :ok = Pricing.update_price(:s3_storage, :standard, 0.0, pricing)
      assert Pricing.get_price(:s3_storage, :standard, pricing) == 0.0
    end

    test "can set price to large value", %{pricing: pricing} do
      :ok = Pricing.update_price(:s3_storage, :standard, 999.999, pricing)
      assert Pricing.get_price(:s3_storage, :standard, pricing) == 999.999
    end
  end

  describe "get_all/1" do
    test "returns a map with all services", %{pricing: pricing} do
      all = Pricing.get_all(pricing)
      assert is_map(all)
      assert map_size(all) >= 6

      expected_keys = [:s3_storage, :s3_put, :s3_get, :glacier_restore,
                       :cross_az_transfer, :dynamodb, :athena]

      Enum.each(expected_keys, fn key ->
        assert Map.has_key?(all, key), "Missing key #{key}"
      end)
    end
  end

  describe "get_service_pricing/2" do
    test "returns full tier map for DynamoDB", %{pricing: pricing} do
      result = Pricing.get_service_pricing(:dynamodb, pricing)
      assert is_map(result)
      assert Map.has_key?(result, :per_rcu)
      assert Map.has_key?(result, :per_wcu)
    end

    test "returns full tier map for cross-AZ transfer", %{pricing: pricing} do
      result = Pricing.get_service_pricing(:cross_az_transfer, pricing)
      assert is_map(result)
      assert Map.has_key?(result, :per_gb)
    end

    test "returns full tier map for Athena", %{pricing: pricing} do
      result = Pricing.get_service_pricing(:athena, pricing)
      assert is_map(result)
      assert Map.has_key?(result, :per_tb_scanned)
    end
  end

  describe "default name functions" do
    test "get_price works with default module name" do
      # Start a Pricing agent with the default module name
      case Compressr.Cost.Pricing.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      assert Pricing.get_price(:s3_storage, :standard) == 0.023
    end

    test "get_service_pricing works with default module name" do
      case Compressr.Cost.Pricing.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      result = Pricing.get_service_pricing(:s3_storage)
      assert is_map(result)
      assert Map.has_key?(result, :standard)
    end

    test "get_all works with default module name" do
      case Compressr.Cost.Pricing.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      all = Pricing.get_all()
      assert is_map(all)
      assert Map.has_key?(all, :s3_storage)
    end

    test "update_price works with default module name" do
      case Compressr.Cost.Pricing.start_link([]) do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      :ok = Pricing.update_price(:s3_storage, :standard, 0.05)
      assert Pricing.get_price(:s3_storage, :standard) == 0.05
      # Reset
      :ok = Pricing.update_price(:s3_storage, :standard, 0.023)
    end
  end

  describe "default_pricing/0" do
    test "contains all expected services" do
      defaults = Pricing.default_pricing()
      assert Map.has_key?(defaults, :s3_storage)
      assert Map.has_key?(defaults, :s3_put)
      assert Map.has_key?(defaults, :s3_get)
      assert Map.has_key?(defaults, :glacier_restore)
      assert Map.has_key?(defaults, :cross_az_transfer)
      assert Map.has_key?(defaults, :dynamodb)
      assert Map.has_key?(defaults, :athena)
    end

    test "glacier storage classes have decreasing prices" do
      defaults = Pricing.default_pricing()
      s3 = defaults.s3_storage
      assert s3.standard > s3.standard_ia
      assert s3.standard_ia > s3.glacier_instant
      assert s3.glacier_instant > s3.glacier_flexible
      assert s3.glacier_flexible > s3.glacier_deep_archive
    end
  end
end
