defmodule Compressr.AuditTest do
  use ExUnit.Case, async: false

  alias Compressr.Audit

  setup do
    clean_audit_items()
    :ok
  end

  describe "log/3" do
    test "logs an audit event with user and metadata" do
      user = %{user_id: "user-1", user_email: "test@example.com"}

      metadata = %{
        resource_type: "source",
        resource_id: "src-123",
        source_ip: "192.168.1.1",
        details: %{"action_detail" => "created syslog source"}
      }

      assert {:ok, event} = Audit.log(:config_created, user, metadata)
      assert event.action == :config_created
      assert event.user_id == "user-1"
      assert event.user_email == "test@example.com"
      assert event.resource_type == "source"
      assert event.resource_id == "src-123"
      assert event.source_ip == "192.168.1.1"
      assert event.details == %{"action_detail" => "created syslog source"}
      assert is_binary(event.id)
      assert is_binary(event.timestamp)
    end

    test "logs an event without user (e.g. login_failed)" do
      assert {:ok, event} =
               Audit.log(:login_failed, nil, %{
                 source_ip: "10.0.0.1",
                 details: %{"reason" => "invalid credentials"}
               })

      assert event.action == :login_failed
      assert event.user_id == nil
      assert event.source_ip == "10.0.0.1"
    end

    test "logs an event with minimal metadata" do
      user = %{user_id: "user-2", user_email: "u2@example.com"}
      assert {:ok, event} = Audit.log(:login, user)
      assert event.action == :login
      assert event.user_id == "user-2"
    end
  end

  describe "query_by_date/2" do
    test "retrieves events logged today" do
      user = %{user_id: "date-user", user_email: "d@example.com"}
      {:ok, _} = Audit.log(:login, user)
      {:ok, _} = Audit.log(:logout, user)

      {:ok, events, _pagination} = Audit.query_by_date(Date.utc_today())
      assert length(events) >= 2

      actions = Enum.map(events, & &1.action)
      assert :login in actions
      assert :logout in actions
    end

    test "returns empty list for a date with no events" do
      {:ok, events, _pagination} = Audit.query_by_date(~D[2020-01-01])
      assert events == []
    end

    test "respects limit option" do
      user = %{user_id: "limit-user", user_email: "l@example.com"}

      for _ <- 1..5 do
        {:ok, _} = Audit.log(:login, user)
      end

      {:ok, events, _pagination} = Audit.query_by_date(Date.utc_today(), limit: 2)
      assert length(events) <= 2
    end
  end

  describe "query_by_user/2" do
    test "filters events by user_id" do
      user_a = %{user_id: "user-a", user_email: "a@example.com"}
      user_b = %{user_id: "user-b", user_email: "b@example.com"}

      {:ok, _} = Audit.log(:login, user_a)
      {:ok, _} = Audit.log(:login, user_b)
      {:ok, _} = Audit.log(:logout, user_a)

      {:ok, events, _pagination} = Audit.query_by_user("user-a")
      assert length(events) >= 2
      assert Enum.all?(events, &(&1.user_id == "user-a"))
    end

    test "returns empty list for unknown user" do
      {:ok, events, _pagination} = Audit.query_by_user("nonexistent-user")
      assert events == []
    end
  end

  describe "query_by_resource/3" do
    test "filters events by resource type and id" do
      user = %{user_id: "res-user", user_email: "r@example.com"}

      {:ok, _} =
        Audit.log(:config_created, user, %{resource_type: "source", resource_id: "src-1"})

      {:ok, _} =
        Audit.log(:config_updated, user, %{resource_type: "source", resource_id: "src-1"})

      {:ok, _} =
        Audit.log(:config_created, user, %{resource_type: "destination", resource_id: "dst-1"})

      {:ok, events, _pagination} = Audit.query_by_resource("source", "src-1")
      assert length(events) >= 2
      assert Enum.all?(events, &(&1.resource_type == "source"))
      assert Enum.all?(events, &(&1.resource_id == "src-1"))
    end
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
