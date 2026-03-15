defmodule Compressr.Audit.StoreTest do
  use ExUnit.Case, async: false

  alias Compressr.Audit.{Store, Event}

  setup do
    clean_audit_items()
    :ok
  end

  describe "log_event/1" do
    test "persists an event to DynamoDB" do
      event = build_event(:login, "store-user-1", "s1@example.com")
      assert :ok = Store.log_event(event)

      # Verify it can be read back
      {:ok, events, _} = Store.query_by_date(Date.utc_today())
      ids = Enum.map(events, & &1.id)
      assert event.id in ids
    end

    test "persists event with all fields" do
      event = %Event{
        id: "test-full-#{System.unique_integer([:positive])}",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        action: :config_created,
        user_id: "store-full-user",
        user_email: "full@example.com",
        resource_type: "pipeline",
        resource_id: "pipe-99",
        source_ip: "10.0.0.42",
        details: %{"key" => "value", "nested" => %{"a" => 1}}
      }

      assert :ok = Store.log_event(event)

      {:ok, events, _} = Store.query_by_date(Date.utc_today())
      found = Enum.find(events, &(&1.id == event.id))

      assert found != nil
      assert found.action == :config_created
      assert found.user_id == "store-full-user"
      assert found.user_email == "full@example.com"
      assert found.resource_type == "pipeline"
      assert found.resource_id == "pipe-99"
      assert found.source_ip == "10.0.0.42"
      assert found.details == %{"key" => "value", "nested" => %{"a" => 1}}
    end

    test "persists event with nil optional fields" do
      event = %Event{
        id: "test-minimal-#{System.unique_integer([:positive])}",
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
        action: :login_failed,
        user_id: nil,
        user_email: nil,
        resource_type: nil,
        resource_id: nil,
        source_ip: nil,
        details: nil
      }

      assert :ok = Store.log_event(event)
    end
  end

  describe "query_by_date/2" do
    test "returns events for the given date" do
      event1 = build_event(:login, "date-u1", "d1@example.com")
      event2 = build_event(:logout, "date-u2", "d2@example.com")
      :ok = Store.log_event(event1)
      :ok = Store.log_event(event2)

      {:ok, events, pagination} = Store.query_by_date(Date.utc_today())
      assert length(events) >= 2
      assert is_map(pagination)
    end

    test "returns empty for date with no events" do
      {:ok, events, _} = Store.query_by_date(~D[2019-06-15])
      assert events == []
    end

    test "supports limit option" do
      for i <- 1..5 do
        :ok = Store.log_event(build_event(:login, "lim-#{i}", "lim#{i}@example.com"))
      end

      {:ok, events, _} = Store.query_by_date(Date.utc_today(), limit: 2)
      assert length(events) <= 2
    end
  end

  describe "query_by_user/2" do
    test "returns events for the given user_id" do
      :ok = Store.log_event(build_event(:login, "target-user", "t@example.com"))
      :ok = Store.log_event(build_event(:logout, "target-user", "t@example.com"))
      :ok = Store.log_event(build_event(:login, "other-user", "o@example.com"))

      {:ok, events, _} = Store.query_by_user("target-user")
      assert length(events) >= 2
      assert Enum.all?(events, &(&1.user_id == "target-user"))
    end
  end

  describe "query_by_resource/3" do
    test "returns events for the given resource" do
      event1 =
        build_event(:config_created, "ru", "r@example.com")
        |> Map.merge(%{resource_type: "source", resource_id: "src-42"})

      event2 =
        build_event(:config_updated, "ru", "r@example.com")
        |> Map.merge(%{resource_type: "source", resource_id: "src-42"})

      event3 =
        build_event(:config_deleted, "ru", "r@example.com")
        |> Map.merge(%{resource_type: "destination", resource_id: "dst-1"})

      :ok = Store.log_event(event1)
      :ok = Store.log_event(event2)
      :ok = Store.log_event(event3)

      {:ok, events, _} = Store.query_by_resource("source", "src-42")
      assert length(events) >= 2
      assert Enum.all?(events, &(&1.resource_type == "source"))
    end
  end

  # Helpers

  defp build_event(action, user_id, user_email) do
    %Event{
      id: "test-#{System.unique_integer([:positive])}",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      action: action,
      user_id: user_id,
      user_email: user_email,
      resource_type: nil,
      resource_id: nil,
      source_ip: "127.0.0.1",
      details: nil
    }
  end

  defp clean_audit_items do
    result =
      ExAws.Dynamo.scan("compressr_test_audit",
        filter_expression: "begins_with(pk, :prefix)",
        expression_attribute_values: [prefix: "audit#"]
      )
      |> ExAws.request!()

    items = Map.get(result, "Items", [])

    Enum.each(items, fn item ->
      pk = get_in(item, ["pk", "S"])
      sk = get_in(item, ["sk", "S"])

      if pk && sk do
        ExAws.Dynamo.delete_item("compressr_test_audit", %{"pk" => pk, "sk" => sk})
        |> ExAws.request!()
      end
    end)
  end
end
