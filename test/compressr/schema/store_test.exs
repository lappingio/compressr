defmodule Compressr.Schema.StoreTest do
  use ExUnit.Case, async: false

  alias Compressr.Schema.{Store, DriftEvent, Schema}

  setup do
    # Clean up any test data
    clean_schemas()
    clean_drift_events()
    :ok
  end

  describe "save_schema/3 and load_schema/1" do
    test "saves and loads a schema" do
      schema = %{
        "host" => %{
          type: :string,
          sample_values: ["server1", "server2"],
          first_seen: DateTime.utc_now()
        },
        "count" => %{
          type: :integer,
          sample_values: [42, 100],
          first_seen: DateTime.utc_now()
        }
      }

      fingerprint = Schema.schema_fingerprint(schema)

      assert :ok = Store.save_schema("test-source-1", schema, fingerprint)

      assert {:ok, {loaded_schema, loaded_fingerprint}} = Store.load_schema("test-source-1")

      assert Map.has_key?(loaded_schema, "host")
      assert Map.has_key?(loaded_schema, "count")
      assert loaded_schema["host"].type == :string
      assert loaded_schema["count"].type == :integer
      assert loaded_fingerprint == fingerprint
    end

    test "returns nil for non-existent source" do
      assert {:ok, nil} = Store.load_schema("nonexistent-source")
    end

    test "overwrites existing schema on re-save" do
      schema1 = %{
        "host" => %{
          type: :string,
          sample_values: ["server1"],
          first_seen: DateTime.utc_now()
        }
      }

      schema2 = %{
        "host" => %{
          type: :string,
          sample_values: ["server1"],
          first_seen: DateTime.utc_now()
        },
        "level" => %{
          type: :string,
          sample_values: ["info"],
          first_seen: DateTime.utc_now()
        }
      }

      fp1 = Schema.schema_fingerprint(schema1)
      fp2 = Schema.schema_fingerprint(schema2)

      Store.save_schema("test-source-2", schema1, fp1)
      Store.save_schema("test-source-2", schema2, fp2)

      {:ok, {loaded, loaded_fp}} = Store.load_schema("test-source-2")

      assert Map.has_key?(loaded, "level")
      assert loaded_fp == fp2
    end
  end

  describe "save_drift_event/1 and load_drift_events/1" do
    test "saves and loads a drift event" do
      drift_event =
        DriftEvent.new(%{
          source_id: "test-source-3",
          drift_type: :new_field,
          field_name: "extra_field",
          old_value: nil,
          new_value: "some_value",
          sample_event: %{"host" => "server1", "extra_field" => "some_value"}
        })

      assert :ok = Store.save_drift_event(drift_event)

      assert {:ok, events} = Store.load_drift_events("test-source-3")
      assert length(events) == 1

      loaded = hd(events)
      assert loaded.source_id == "test-source-3"
      assert loaded.drift_type == :new_field
      assert loaded.field_name == "extra_field"
    end

    test "loads multiple drift events in order" do
      now = DateTime.utc_now()

      for {i, type} <- [{0, :new_field}, {1, :missing_field}, {2, :type_change}] do
        timestamp = DateTime.add(now, i, :second)

        DriftEvent.new(%{
          source_id: "test-source-4",
          timestamp: timestamp,
          drift_type: type,
          field_name: "field_#{i}",
          old_value: nil,
          new_value: nil
        })
        |> Store.save_drift_event()
      end

      {:ok, events} = Store.load_drift_events("test-source-4")
      assert length(events) == 3

      types = Enum.map(events, & &1.drift_type)
      assert types == [:new_field, :missing_field, :type_change]
    end

    test "returns empty list for source with no drift events" do
      assert {:ok, []} = Store.load_drift_events("no-drift-source")
    end

    test "saves drift event without sample_event" do
      drift_event =
        DriftEvent.new(%{
          source_id: "test-source-5",
          drift_type: :missing_field,
          field_name: "removed_field"
        })

      assert :ok = Store.save_drift_event(drift_event)

      {:ok, events} = Store.load_drift_events("test-source-5")
      assert length(events) == 1
      assert hd(events).sample_event == nil
    end
  end

  # --- Cleanup helpers ---

  defp clean_schemas do
    clean_by_pk("schema")
  end

  defp clean_drift_events do
    clean_by_pk("drift")
  end

  defp clean_by_pk(pk_value) do
    result =
      ExAws.Dynamo.scan(table_name(),
        filter_expression: "pk = :pk",
        expression_attribute_values: [pk: pk_value]
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk_val = get_in(item, ["pk", "S"])
      sk_val = get_in(item, ["sk", "S"])

      ExAws.Dynamo.delete_item(table_name(), %{"pk" => pk_val, "sk" => sk_val})
      |> ExAws.request!()
    end)
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}schemas"
  end
end
