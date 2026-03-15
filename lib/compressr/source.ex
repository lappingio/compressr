defmodule Compressr.Source do
  @moduledoc """
  Behaviour for Compressr data sources.

  All source types (syslog, HEC, S3, etc.) implement this behaviour.
  Sources receive or retrieve data and emit `Compressr.Event` structs.
  """

  @doc """
  Initialize the source with its configuration.

  Returns `{:ok, state}` on success or `{:error, reason}` on failure.
  """
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, reason :: term()}

  @doc """
  Handle incoming data and produce events.

  Returns `{:ok, events, new_state}` where events is a list of `Compressr.Event` maps.
  """
  @callback handle_data(data :: binary(), state :: term()) ::
              {:ok, [map()], state :: term()}

  @doc """
  Stop the source and clean up resources.
  """
  @callback stop(state :: term()) :: :ok

  @doc """
  Validate source-specific configuration.

  Returns `:ok` if valid, `{:error, reason}` if invalid.
  """
  @callback validate_config(config :: map()) :: :ok | {:error, reason :: term()}

  @optional_callbacks [validate_config: 1]

  @doc """
  Returns the source module for a given type string.
  """
  @spec module_for_type(String.t()) :: {:ok, module()} | {:error, :unknown_type}
  def module_for_type("syslog"), do: {:ok, Compressr.Source.Syslog}
  def module_for_type("hec"), do: {:ok, Compressr.Source.HEC}
  def module_for_type(_), do: {:error, :unknown_type}

  @doc """
  Validates configuration for a given source type.
  """
  @spec validate_config_for_type(String.t(), map()) :: :ok | {:error, term()}
  def validate_config_for_type(type, config) do
    case module_for_type(type) do
      {:ok, mod} ->
        if function_exported?(mod, :validate_config, 1) do
          mod.validate_config(config)
        else
          :ok
        end

      {:error, _} = err ->
        err
    end
  end
end
