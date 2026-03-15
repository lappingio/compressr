defmodule Compressr.Telemetry.Reporter do
  @moduledoc """
  Simple console/log reporter for development and debugging.

  Attaches to Compressr telemetry events and logs them as structured JSON
  via Elixir's Logger. Useful for debugging without external monitoring.

  ## Configuration

  - `:events` - List of event names to attach to. Defaults to all events.
  - `:sample_rate` - Float between 0.0 and 1.0. Probability of logging each event.
    Defaults to 1.0 (log everything).
  - `:level` - Logger level for emitted log lines. Defaults to `:info`.

  ## Usage

      # Attach to all events
      Compressr.Telemetry.Reporter.attach()

      # Attach with options
      Compressr.Telemetry.Reporter.attach(
        events: [[:compressr, :events, :in], [:compressr, :events, :out]],
        sample_rate: 0.1,
        level: :debug
      )

      # Detach
      Compressr.Telemetry.Reporter.detach()
  """

  require Logger

  @handler_prefix "compressr-reporter"

  @doc """
  Attach the reporter to telemetry events.

  ## Options

    - `:events` - List of event names. Defaults to `Compressr.Telemetry.all_events/0`.
    - `:sample_rate` - Float 0.0-1.0. Defaults to 1.0.
    - `:level` - Logger level. Defaults to `:info`.
  """
  def attach(opts \\ []) do
    events = Keyword.get(opts, :events, Compressr.Telemetry.all_events())
    sample_rate = Keyword.get(opts, :sample_rate, 1.0)
    level = Keyword.get(opts, :level, :info)

    config = %{sample_rate: sample_rate, level: level}

    for event <- events do
      handler_id = handler_id(event)

      :telemetry.attach(
        handler_id,
        event,
        &__MODULE__.handle_event/4,
        config
      )
    end

    :ok
  end

  @doc """
  Detach the reporter from all telemetry events.
  """
  def detach do
    events = Compressr.Telemetry.all_events()

    for event <- events do
      handler_id = handler_id(event)
      :telemetry.detach(handler_id)
    end

    :ok
  end

  @doc false
  def handle_event(event, measurements, metadata, %{sample_rate: rate, level: level}) do
    if should_sample?(rate) do
      log_entry = %{
        event: Enum.join(event, "."),
        measurements: measurements,
        metadata: stringify_metadata(metadata),
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      }

      Logger.log(level, Jason.encode!(log_entry))
    end
  end

  defp should_sample?(1.0), do: true
  defp should_sample?(rate), do: :rand.uniform() <= rate

  defp handler_id(event) do
    "#{@handler_prefix}-#{Enum.join(event, "-")}"
  end

  defp stringify_metadata(metadata) do
    Map.new(metadata, fn {k, v} -> {k, to_string(v)} end)
  end
end
