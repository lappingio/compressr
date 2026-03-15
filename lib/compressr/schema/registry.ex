defmodule Compressr.Schema.Registry do
  @moduledoc """
  Schema Registry context module.

  Provides the public API for log type discovery, classification, schema
  tracking, and querying. Built on top of the existing schema drift detection
  infrastructure.

  ## Key operations

    * `discover/2` - classify events, infer schemas, return discovery report
    * `get_log_types/1` - list all detected log types for a source
    * `get_schema/2` - get schema for a specific log type
    * `get_volume_breakdown/1` - volume breakdown by log type for a source
    * `search_fields/1` - search for a field across all log types
    * `get_schema_history/2` - get version history for a log type's schema

  """

  alias Compressr.Schema.Schema
  alias Compressr.Schema.Registry.{Classifier, LogType, SchemaVersion, VolumeTracker}

  @type discovery_report :: %{
          source_id: String.t(),
          log_types: [LogType.t()],
          total_events: non_neg_integer(),
          classification_rules: [Classifier.classification_rule()]
        }

  @doc """
  Discover log types within a batch of events for a source.

  Classifies events using structural fingerprinting (and optional rules),
  infers per-type schemas, and returns a discovery report.

  ## Options

    * `:rules` - classification rules (field presence, regex)
    * `:volume_tracker` - pid/name of VolumeTracker to record metrics (optional)

  ## Returns

  A discovery report map with:
    * `:source_id` - the source identifier
    * `:log_types` - list of `%LogType{}` structs with inferred schemas
    * `:total_events` - total events processed

  """
  @spec discover(String.t(), [map()], keyword()) :: discovery_report()
  def discover(source_id, events, opts \\ []) when is_binary(source_id) and is_list(events) do
    rules = Keyword.get(opts, :rules, [])
    volume_tracker = Keyword.get(opts, :volume_tracker, nil)

    # Classify events into groups by log type
    grouped = Classifier.classify_batch(events, rules: rules)

    # Build log types with inferred schemas
    log_types =
      Enum.map(grouped, fn {log_type_id, type_events} ->
        # Infer schema from all events of this type
        schema =
          Enum.reduce(type_events, Schema.new(), fn event, acc ->
            Schema.merge(acc, event)
          end)

        # Compute fingerprint from the first event
        fingerprint = Classifier.fingerprint(hd(type_events))

        # Determine classification method
        method =
          if Enum.any?(rules) do
            # Check if this type was matched by a rule
            test_event = hd(type_events)
            case try_rules(test_event, rules) do
              {:ok, ^log_type_id} -> :rule
              _ -> :structural
            end
          else
            :structural
          end

        # Record volume if tracker provided
        if volume_tracker do
          Enum.each(type_events, fn event ->
            byte_size = event |> inspect() |> byte_size()
            VolumeTracker.record(volume_tracker, source_id, log_type_id, byte_size)
          end)
        end

        # Emit telemetry
        :telemetry.execute(
          [:compressr, :schema_registry, :log_type_detected],
          %{count: 1},
          %{source_id: source_id, log_type_id: log_type_id}
        )

        LogType.new(%{
          id: log_type_id,
          source_id: source_id,
          fingerprint: fingerprint,
          classification_method: method,
          event_count: length(type_events),
          schema: schema
        })
      end)

    # Emit classification telemetry
    :telemetry.execute(
      [:compressr, :schema_registry, :events_classified],
      %{count: length(events)},
      %{source_id: source_id}
    )

    %{
      source_id: source_id,
      log_types: log_types,
      total_events: length(events)
    }
  end

  @doc """
  Get all detected log types for a source.

  Uses in-memory state only (does not query DynamoDB). Pass a list of
  log types from a previous discovery report or maintain state externally.
  """
  @spec get_log_types(String.t(), [LogType.t()]) :: [LogType.t()]
  def get_log_types(source_id, log_types) when is_binary(source_id) and is_list(log_types) do
    Enum.filter(log_types, fn lt -> lt.source_id == source_id end)
  end

  @doc """
  Get schema for a specific log type within a source.

  Searches the provided list of log types for a matching source_id and log_type_id.
  """
  @spec get_schema(String.t(), String.t(), [LogType.t()]) :: {:ok, map()} | :not_found
  def get_schema(source_id, log_type_id, log_types)
      when is_binary(source_id) and is_binary(log_type_id) and is_list(log_types) do
    case Enum.find(log_types, fn lt ->
           lt.source_id == source_id and lt.id == log_type_id
         end) do
      %LogType{schema: schema} -> {:ok, schema}
      nil -> :not_found
    end
  end

  @doc """
  Get volume breakdown for a source from the VolumeTracker.
  """
  @spec get_volume_breakdown(GenServer.server(), String.t()) :: map()
  def get_volume_breakdown(volume_tracker \\ VolumeTracker, source_id)
      when is_binary(source_id) do
    VolumeTracker.get_breakdown(volume_tracker, source_id)
  end

  @doc """
  Search for a field name across all known log types.

  Returns a list of matches with log type context.
  """
  @spec search_fields(String.t(), [LogType.t()]) :: [map()]
  def search_fields(field_name, log_types)
      when is_binary(field_name) and is_list(log_types) do
    Enum.flat_map(log_types, fn log_type ->
      case Map.get(log_type.schema, field_name) do
        nil ->
          []

        field_info ->
          [
            %{
              source_id: log_type.source_id,
              log_type_id: log_type.id,
              log_type_name: log_type.name,
              field_name: field_name,
              field_type: field_info.type,
              sample_values: field_info.sample_values
            }
          ]
      end
    end)
  end

  @doc """
  Get schema version history for a log type.

  Takes a list of SchemaVersion structs and returns them sorted by version.
  """
  @spec get_schema_history([SchemaVersion.t()]) :: [SchemaVersion.t()]
  def get_schema_history(versions) when is_list(versions) do
    Enum.sort_by(versions, & &1.version)
  end

  # --- Private ---

  defp try_rules(event, rules) do
    Enum.reduce_while(rules, :no_match, fn rule, _acc ->
      case match_rule(event, rule) do
        {:ok, id} -> {:halt, {:ok, id}}
        :no_match -> {:cont, :no_match}
      end
    end)
  end

  defp match_rule(event, {:field_presence, %{fields: required_fields, log_type_id: log_type_id}}) do
    user_fields = Schema.user_fields(event)
    field_keys = Map.keys(user_fields)

    if Enum.all?(required_fields, &(&1 in field_keys)) do
      {:ok, log_type_id}
    else
      :no_match
    end
  end

  defp match_rule(event, {:regex, %{pattern: pattern, log_type_id: log_type_id}}) do
    raw = Map.get(event, "_raw", "")

    if is_binary(raw) and Regex.match?(pattern, raw) do
      {:ok, log_type_id}
    else
      :no_match
    end
  end

  defp match_rule(_event, _), do: :no_match
end
