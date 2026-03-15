defmodule Compressr.LocalStackSmokeTest do
  @moduledoc """
  Smoke tests verifying LocalStack services are working correctly.
  These tests ensure the development environment is properly configured.
  """
  use ExUnit.Case, async: false

  @test_bucket "compressr-test-events"
  @test_table "compressr_test_config"

  describe "S3" do
    test "can put and get an object" do
      key = "smoke-test/#{System.unique_integer([:positive])}.json"
      body = Jason.encode!(%{test: true, timestamp: DateTime.utc_now()})

      assert {:ok, _} = ExAws.S3.put_object(@test_bucket, key, body) |> ExAws.request()
      assert {:ok, %{body: ^body}} = ExAws.S3.get_object(@test_bucket, key) |> ExAws.request()

      # Cleanup
      ExAws.S3.delete_object(@test_bucket, key) |> ExAws.request()
    end

    test "can list objects with prefix" do
      prefix = "smoke-list/#{System.unique_integer([:positive])}/"

      for i <- 1..3 do
        ExAws.S3.put_object(@test_bucket, "#{prefix}file-#{i}.json", "data-#{i}")
        |> ExAws.request()
      end

      {:ok, %{body: %{contents: objects}}} =
        ExAws.S3.list_objects(@test_bucket, prefix: prefix) |> ExAws.request()

      assert length(objects) == 3

      # Cleanup
      for i <- 1..3 do
        ExAws.S3.delete_object(@test_bucket, "#{prefix}file-#{i}.json") |> ExAws.request()
      end
    end
  end

  describe "DynamoDB" do
    test "can put and get an item" do
      item = %{
        "pk" => "test-source-1",
        "sk" => "config",
        "name" => "Test Source",
        "type" => "syslog",
        "enabled" => true
      }

      assert {:ok, _} =
               ExAws.Dynamo.put_item(@test_table, item) |> ExAws.request()

      assert {:ok, %{"Item" => returned}} =
               ExAws.Dynamo.get_item(@test_table, %{"pk" => "test-source-1", "sk" => "config"})
               |> ExAws.request()

      assert returned["name"]["S"] == "Test Source"

      # Cleanup
      ExAws.Dynamo.delete_item(@test_table, %{"pk" => "test-source-1", "sk" => "config"})
      |> ExAws.request()
    end

    test "can query items by partition key" do
      for i <- 1..3 do
        ExAws.Dynamo.put_item(@test_table, %{
          "pk" => "query-test",
          "sk" => "item-#{i}",
          "data" => "value-#{i}"
        })
        |> ExAws.request()
      end

      {:ok, %{"Items" => items}} =
        ExAws.Dynamo.query(
          @test_table,
          expression_attribute_values: [pk: "query-test"],
          key_condition_expression: "pk = :pk"
        )
        |> ExAws.request()

      assert length(items) == 3

      # Cleanup
      for i <- 1..3 do
        ExAws.Dynamo.delete_item(@test_table, %{"pk" => "query-test", "sk" => "item-#{i}"})
        |> ExAws.request()
      end
    end
  end

  describe "SQS" do
    test "can create queue, send, and receive messages" do
      queue_name = "compressr-smoke-test-#{System.unique_integer([:positive])}"

      {:ok, %{body: %{queue_url: queue_url}}} =
        ExAws.SQS.create_queue(queue_name) |> ExAws.request()

      assert {:ok, _} =
               ExAws.SQS.send_message(queue_url, Jason.encode!(%{event: "test"}))
               |> ExAws.request()

      {:ok, %{body: %{messages: messages}}} =
        ExAws.SQS.receive_message(queue_url, max_number_of_messages: 1)
        |> ExAws.request()

      assert length(messages) == 1
      assert %{event: "test"} = Jason.decode!(hd(messages).body, keys: :atoms)

      # Cleanup
      ExAws.SQS.delete_queue(queue_url) |> ExAws.request()
    end
  end
end
