defmodule CompressrWeb.Api.DestinationControllerExtraTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Destination.Config

  setup do
    clean_items("destination")
    :ok
  end

  describe "POST /api/v1/system/outputs with backpressure modes" do
    test "creates destination with drop backpressure mode", %{conn: conn} do
      params = %{
        "id" => "dest-bp-drop",
        "name" => "Drop Mode Dest",
        "type" => "devnull",
        "config" => %{},
        "backpressure_mode" => "drop"
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["backpressure_mode"] == "drop"
    end

    test "creates destination with queue backpressure mode", %{conn: conn} do
      params = %{
        "id" => "dest-bp-queue",
        "name" => "Queue Mode Dest",
        "type" => "devnull",
        "config" => %{},
        "backpressure_mode" => "queue"
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["backpressure_mode"] == "queue"
    end

    test "defaults to block backpressure mode", %{conn: conn} do
      params = %{
        "id" => "dest-bp-default",
        "name" => "Default BP Dest",
        "type" => "devnull",
        "config" => %{}
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["backpressure_mode"] == "block"
    end

    test "creates destination with post_processing_pipeline_id", %{conn: conn} do
      params = %{
        "id" => "dest-pp",
        "name" => "Post Pipeline Dest",
        "type" => "s3",
        "config" => %{"bucket" => "test"},
        "post_processing_pipeline_id" => "pp-123"
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["post_processing_pipeline_id"] == "pp-123"
    end

    test "creates destination with enabled=false", %{conn: conn} do
      params = %{
        "id" => "dest-disabled",
        "name" => "Disabled Dest",
        "type" => "devnull",
        "config" => %{},
        "enabled" => false
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["enabled"] == false
    end
  end

  describe "PATCH /api/v1/system/outputs/:id with various fields" do
    test "updates backpressure_mode", %{conn: conn} do
      {:ok, _} = Config.save(%Config{
        id: "dest-patch-bp",
        name: "Patch BP",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      })

      params = %{"backpressure_mode" => "drop"}
      conn = patch(conn, ~p"/api/v1/system/outputs/dest-patch-bp", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["backpressure_mode"] == "drop"
    end

    test "updates enabled flag", %{conn: conn} do
      {:ok, _} = Config.save(%Config{
        id: "dest-patch-en",
        name: "Patch Enabled",
        type: "devnull",
        config: %{},
        enabled: true,
        backpressure_mode: :block
      })

      params = %{"enabled" => false}
      conn = patch(conn, ~p"/api/v1/system/outputs/dest-patch-en", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["enabled"] == false
    end

    test "updates config", %{conn: conn} do
      {:ok, _} = Config.save(%Config{
        id: "dest-patch-cfg",
        name: "Patch Config",
        type: "s3",
        config: %{"bucket" => "old-bucket"},
        enabled: true,
        backpressure_mode: :block
      })

      params = %{"config" => %{"bucket" => "new-bucket"}}
      conn = patch(conn, ~p"/api/v1/system/outputs/dest-patch-cfg", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["config"] == %{"bucket" => "new-bucket"}
    end
  end

  describe "POST /api/v1/system/outputs - create edge cases" do
    test "creates with nil config", %{conn: conn} do
      params = %{
        "id" => "dest-nil-cfg",
        "name" => "Nil Config",
        "type" => "devnull"
      }

      conn = post(conn, ~p"/api/v1/system/outputs", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["config"] == %{}
    end
  end

  defp clean_items(pk_value) do
    table = "compressr_test_config"

    result =
      ExAws.Dynamo.scan(table,
        filter_expression: "pk = :pk",
        expression_attribute_values: %{"pk" => pk_value}
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk = get_in(item, ["pk", "S"])
      sk = get_in(item, ["sk", "S"])
      ExAws.Dynamo.delete_item(table, %{"pk" => pk, "sk" => sk}) |> ExAws.request!()
    end)
  end
end
