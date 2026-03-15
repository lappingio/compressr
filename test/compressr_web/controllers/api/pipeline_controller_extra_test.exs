defmodule CompressrWeb.Api.PipelineControllerExtraTest do
  use CompressrWeb.ConnCase, async: false

  alias Compressr.Pipeline.Config

  setup do
    clean_items("pipeline")
    :ok
  end

  describe "POST /api/v1/system/pipelines with edge cases" do
    test "creates pipeline with description", %{conn: conn} do
      params = %{
        "id" => "pipe-desc",
        "name" => "Described Pipeline",
        "description" => "This pipeline does interesting things",
        "functions" => []
      }

      conn = post(conn, ~p"/api/v1/system/pipelines", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["description"] == "This pipeline does interesting things"
    end

    test "creates pipeline with enabled=false", %{conn: conn} do
      params = %{
        "id" => "pipe-disabled",
        "name" => "Disabled Pipeline",
        "enabled" => false,
        "functions" => []
      }

      conn = post(conn, ~p"/api/v1/system/pipelines", params)
      response = json_response(conn, 201)
      assert [item] = response["items"]
      assert item["enabled"] == false
    end

    test "returns error when name is empty", %{conn: conn} do
      params = %{"id" => "pipe-no-name", "name" => ""}
      conn = post(conn, ~p"/api/v1/system/pipelines", params)
      assert json_response(conn, 422)
    end
  end

  describe "PATCH /api/v1/system/pipelines/:id edge cases" do
    test "updates description", %{conn: conn} do
      {:ok, _} = Config.save(%{"id" => "pipe-upd-desc", "name" => "Original"})

      params = %{"description" => "Updated description"}
      conn = patch(conn, ~p"/api/v1/system/pipelines/pipe-upd-desc", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["description"] == "Updated description"
    end

    test "updates functions list", %{conn: conn} do
      {:ok, _} = Config.save(%{
        "id" => "pipe-upd-funcs",
        "name" => "Funcs Pipeline",
        "functions" => []
      })

      params = %{"functions" => [%{"type" => "eval", "config" => %{}}]}
      conn = patch(conn, ~p"/api/v1/system/pipelines/pipe-upd-funcs", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert length(item["functions"]) == 1
    end

    test "updates enabled flag", %{conn: conn} do
      {:ok, _} = Config.save(%{"id" => "pipe-upd-en", "name" => "Enable Toggle"})

      params = %{"enabled" => false}
      conn = patch(conn, ~p"/api/v1/system/pipelines/pipe-upd-en", params)
      response = json_response(conn, 200)
      assert [item] = response["items"]
      assert item["enabled"] == false
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
