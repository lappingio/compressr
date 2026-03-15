defmodule Compressr.Test.LocalStack do
  @moduledoc """
  Helpers for setting up and tearing down LocalStack resources in tests.

  ## Usage

  Call `ensure_running!/0` in test_helper.exs to verify LocalStack is available.
  Call `setup_resources!/0` to create DynamoDB tables and S3 buckets.
  Call `cleanup_resources!/0` to tear down everything between test runs.
  """

  @localstack_url "http://localhost:4566"
  @health_url "#{@localstack_url}/_localstack/health"

  # Tables defined as {key_schema, attribute_definitions}
  # key_schema: keyword list of {attr_name, key_type}
  # attribute_definitions: keyword list of {attr_name, attr_type}
  @dynamodb_tables %{
    "compressr_test_config" => %{
      key_schema: [pk: :hash, sk: :range],
      attribute_definitions: [pk: :string, sk: :string]
    },
    "compressr_test_schemas" => %{
      key_schema: [pk: :hash, sk: :range],
      attribute_definitions: [pk: :string, sk: :string]
    },
    "compressr_test_collection_state" => %{
      key_schema: [pk: :hash, sk: :range],
      attribute_definitions: [pk: :string, sk: :string]
    },
    "compressr_test_audit" => %{
      key_schema: [pk: :hash, sk: :range],
      attribute_definitions: [pk: :string, sk: :string]
    }
  }

  @s3_buckets ["compressr-test-events", "compressr-test-archive"]

  def ensure_running! do
    case :httpc.request(:get, {~c"#{@health_url}", []}, [timeout: 2000], []) do
      {:ok, {{_, 200, _}, _, _}} ->
        :ok

      _ ->
        raise """
        LocalStack is not running!

        Start it with:
            docker compose up -d

        Then re-run tests:
            mix test
        """
    end
  end

  def setup_resources! do
    create_dynamodb_tables!()
    create_s3_buckets!()
    :ok
  end

  def cleanup_resources! do
    delete_dynamodb_tables!()
    empty_and_delete_s3_buckets!()
    :ok
  end

  def reset_resources! do
    cleanup_resources!()
    setup_resources!()
  end

  defp create_dynamodb_tables! do
    Enum.each(@dynamodb_tables, fn {table_name, schema} ->
      ExAws.Dynamo.create_table(
        table_name,
        schema.key_schema,
        schema.attribute_definitions,
        1, 1
      )
      |> ExAws.request()
      |> case do
        {:ok, _} -> :ok
        {:error, {"ResourceInUseException", _}} -> :ok
        {:error, error} -> raise "Failed to create DynamoDB table #{table_name}: #{inspect(error)}"
      end
    end)
  end

  defp create_s3_buckets! do
    Enum.each(@s3_buckets, fn bucket ->
      ExAws.S3.put_bucket(bucket, "us-east-1")
      |> ExAws.request()
      |> case do
        {:ok, _} -> :ok
        {:error, {:http_error, 409, _}} -> :ok
        {:error, error} -> raise "Failed to create S3 bucket #{bucket}: #{inspect(error)}"
      end
    end)
  end

  defp delete_dynamodb_tables! do
    Enum.each(@dynamodb_tables, fn {table_name, _} ->
      ExAws.Dynamo.delete_table(table_name)
      |> ExAws.request()
      |> case do
        {:ok, _} -> :ok
        {:error, {"ResourceNotFoundException", _}} -> :ok
        {:error, _} -> :ok
      end
    end)
  end

  defp empty_and_delete_s3_buckets! do
    Enum.each(@s3_buckets, fn bucket ->
      # List and delete all objects first
      case ExAws.S3.list_objects(bucket) |> ExAws.request() do
        {:ok, %{body: %{contents: objects}}} when is_list(objects) ->
          Enum.each(objects, fn obj ->
            ExAws.S3.delete_object(bucket, obj.key) |> ExAws.request()
          end)
        _ -> :ok
      end

      ExAws.S3.delete_bucket(bucket)
      |> ExAws.request()
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end)
  end
end
