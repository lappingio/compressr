defmodule Compressr.Expression do
  @moduledoc """
  Public API for the compressr expression language.

  A VRL-inspired expression language that compiles to BEAM-native functions.
  Expressions are parsed and compiled at configuration time, producing closures
  that can be evaluated per-event with no interpretation overhead.

  ## Examples

      iex> {:ok, fun} = Compressr.Expression.compile(".severity > 3")
      iex> Compressr.Expression.evaluate(fun, %{"severity" => 5})
      true

      iex> {:ok, fun} = Compressr.Expression.compile(~s(.source == "cloudtrail" and .severity > 3))
      iex> Compressr.Expression.evaluate(fun, %{"source" => "cloudtrail", "severity" => 5})
      true
  """

  alias Compressr.Expression.{Parser, Compiler}

  @doc """
  Parses and compiles an expression string to a function.

  Returns `{:ok, fun}` where `fun` is a function that takes an event map
  and returns the expression result, or `{:error, reason}`.
  """
  @spec compile(String.t()) :: {:ok, (map() -> any())} | {:error, String.t()}
  def compile(expression) when is_binary(expression) do
    with {:ok, ast} <- Parser.parse(expression),
         {:ok, fun} <- Compiler.compile(ast) do
      {:ok, fun}
    end
  end

  @doc """
  Same as `compile/1` but raises on error.
  """
  @spec compile!(String.t()) :: (map() -> any())
  def compile!(expression) when is_binary(expression) do
    case compile(expression) do
      {:ok, fun} -> fun
      {:error, reason} -> raise ArgumentError, "failed to compile expression: #{reason}"
    end
  end

  @doc """
  Evaluates a compiled expression function against an event.

  Returns the result value of the expression.
  """
  @spec evaluate((map() -> any()), map()) :: any()
  def evaluate(compiled_fn, event) when is_function(compiled_fn, 1) and is_map(event) do
    compiled_fn.(event)
  end

  @doc """
  Checks if an expression string is valid (compiles without error).
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(expression) when is_binary(expression) do
    case compile(expression) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end
end
