defmodule Compressr.Config.CacheTest do
  use ExUnit.Case, async: false

  alias Compressr.Config.Cache

  @test_items [
    %{"id" => "src-1", "name" => "Test Source", "type" => "syslog", "enabled" => true},
    %{"id" => "src-2", "name" => "Another Source", "type" => "hec", "enabled" => false}
  ]

  setup do
    # Use a unique temp directory for each test to avoid conflicts
    test_dir = Path.join(System.tmp_dir!(), "compressr_cache_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(test_dir)

    # Configure the cache dir for this test
    prev = Application.get_env(:compressr, :config_cache_dir)
    Application.put_env(:compressr, :config_cache_dir, test_dir)

    on_exit(fn ->
      if prev do
        Application.put_env(:compressr, :config_cache_dir, prev)
      else
        Application.delete_env(:compressr, :config_cache_dir)
      end

      File.rm_rf!(test_dir)
    end)

    %{test_dir: test_dir}
  end

  describe "write_cache/2 and read_cache/1" do
    test "writes and reads sources cache", %{test_dir: _dir} do
      assert :ok = Cache.write_cache(:sources, @test_items)
      assert {:ok, items} = Cache.read_cache(:sources)
      assert length(items) == 2
      assert Enum.at(items, 0)["id"] == "src-1"
      assert Enum.at(items, 1)["id"] == "src-2"
    end

    test "writes and reads destinations cache" do
      dest_items = [%{"id" => "dest-1", "name" => "S3 Dest", "type" => "s3"}]
      assert :ok = Cache.write_cache(:destinations, dest_items)
      assert {:ok, items} = Cache.read_cache(:destinations)
      assert length(items) == 1
      assert Enum.at(items, 0)["id"] == "dest-1"
    end

    test "writes and reads pipelines cache" do
      assert :ok = Cache.write_cache(:pipelines, [])
      assert {:ok, []} = Cache.read_cache(:pipelines)
    end

    test "writes and reads routes cache" do
      route_items = [%{"id" => "route-1", "source_id" => "src-1", "destination_id" => "dest-1"}]
      assert :ok = Cache.write_cache(:routes, route_items)
      assert {:ok, items} = Cache.read_cache(:routes)
      assert length(items) == 1
    end

    test "overwrites existing cache" do
      assert :ok = Cache.write_cache(:sources, @test_items)
      new_items = [%{"id" => "src-3", "name" => "New Source"}]
      assert :ok = Cache.write_cache(:sources, new_items)
      assert {:ok, items} = Cache.read_cache(:sources)
      assert length(items) == 1
      assert Enum.at(items, 0)["id"] == "src-3"
    end
  end

  describe "read_cache/1 error cases" do
    test "returns :not_found when cache file does not exist" do
      assert {:error, :not_found} = Cache.read_cache(:sources)
    end

    test "returns :corrupted when cache contains invalid JSON", %{test_dir: dir} do
      path = Path.join(dir, "sources.json")
      File.write!(path, "this is not json {{{")
      assert {:error, :corrupted} = Cache.read_cache(:sources)
    end

    test "returns :corrupted when cache contains valid JSON but not a list", %{test_dir: dir} do
      path = Path.join(dir, "sources.json")
      File.write!(path, Jason.encode!(%{"not" => "a list"}))
      assert {:error, :corrupted} = Cache.read_cache(:sources)
    end
  end

  describe "write_cache/2 validation" do
    test "rejects invalid resource types" do
      assert {:error, {:invalid_resource_type, :invalid}} = Cache.write_cache(:invalid, [])
    end
  end

  describe "cache_path/1" do
    test "returns path based on resource type", %{test_dir: dir} do
      assert Cache.cache_path(:sources) == Path.join(dir, "sources.json")
      assert Cache.cache_path(:destinations) == Path.join(dir, "destinations.json")
      assert Cache.cache_path(:pipelines) == Path.join(dir, "pipelines.json")
      assert Cache.cache_path(:routes) == Path.join(dir, "routes.json")
    end
  end
end
