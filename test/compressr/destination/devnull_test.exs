defmodule Compressr.Destination.DevNullTest do
  use ExUnit.Case, async: true

  alias Compressr.Destination.DevNull
  alias Compressr.Event

  describe "init/1" do
    test "initializes with empty config" do
      assert {:ok, %DevNull{events_discarded: 0}} = DevNull.init(%{})
    end

    test "initializes with arbitrary config (ignored)" do
      assert {:ok, %DevNull{}} = DevNull.init(%{"any" => "config"})
    end
  end

  describe "send_batch/2" do
    test "discards all events and always succeeds" do
      {:ok, state} = DevNull.init(%{})

      events = [
        Event.new(%{"_raw" => "event 1"}),
        Event.new(%{"_raw" => "event 2"}),
        Event.new(%{"_raw" => "event 3"})
      ]

      assert {:ok, new_state} = DevNull.send_batch(events, state)
      assert new_state.events_discarded == 3
    end

    test "accumulates discarded event count across batches" do
      {:ok, state} = DevNull.init(%{})

      {:ok, state} = DevNull.send_batch([Event.new()], state)
      {:ok, state} = DevNull.send_batch([Event.new(), Event.new()], state)
      {:ok, state} = DevNull.send_batch([Event.new()], state)

      assert state.events_discarded == 4
    end

    test "handles empty batch" do
      {:ok, state} = DevNull.init(%{})
      assert {:ok, new_state} = DevNull.send_batch([], state)
      assert new_state.events_discarded == 0
    end
  end

  describe "flush/1" do
    test "always succeeds (no-op)" do
      {:ok, state} = DevNull.init(%{})
      assert {:ok, ^state} = DevNull.flush(state)
    end
  end

  describe "stop/1" do
    test "always returns :ok" do
      {:ok, state} = DevNull.init(%{})
      assert :ok = DevNull.stop(state)
    end
  end

  describe "healthy?/1" do
    test "always reports healthy" do
      {:ok, state} = DevNull.init(%{})
      assert DevNull.healthy?(state) == true
    end
  end
end
