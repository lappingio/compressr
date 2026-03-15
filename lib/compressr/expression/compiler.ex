defmodule Compressr.Expression.Compiler do
  @moduledoc """
  Compiles an expression AST into an Elixir function.

  The resulting function takes an event map and returns a value.
  Uses closures built from the AST — no `Code.eval_string`.
  """

  alias Compressr.Expression.Functions

  @known_functions ~w(exists length downcase upcase to_int to_float to_string now contains starts_with ends_with match)

  @doc """
  Compiles an AST node into a function that takes an event map and returns a value.

  Returns `{:ok, fun}` or `{:error, reason}`.
  """
  @spec compile(any()) :: {:ok, (map() -> any())} | {:error, String.t()}
  def compile(ast) do
    {:ok, compile_node(ast)}
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc "Same as `compile/1` but raises on error."
  @spec compile!(any()) :: (map() -> any())
  def compile!(ast) do
    case compile(ast) do
      {:ok, fun} -> fun
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # --- Node compilation ---

  defp compile_node({:literal, value}) do
    fn _event -> value end
  end

  defp compile_node({:field, path}) do
    fn event ->
      case Functions.get_nested(event, path) do
        :field_missing -> nil
        value -> value
      end
    end
  end

  defp compile_node({:binary_op, :and, left, right}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> truthy?(left_fn.(event)) and truthy?(right_fn.(event)) end
  end

  defp compile_node({:binary_op, :or, left, right}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> truthy?(left_fn.(event)) or truthy?(right_fn.(event)) end
  end

  defp compile_node({:binary_op, op, left, right})
       when op in [:==, :!=, :>, :<, :>=, :<=] do
    left_fn = compile_node(left)
    right_fn = compile_node(right)

    fn event ->
      l = left_fn.(event)
      r = right_fn.(event)
      apply_comparison(op, l, r)
    end
  end

  defp compile_node({:binary_op, op, left, right}) when op in [:+, :-, :*, :/] do
    left_fn = compile_node(left)
    right_fn = compile_node(right)

    fn event ->
      l = left_fn.(event)
      r = right_fn.(event)
      apply_arithmetic(op, l, r)
    end
  end

  defp compile_node({:unary_op, :not, expr}) do
    expr_fn = compile_node(expr)
    fn event -> not truthy?(expr_fn.(event)) end
  end

  defp compile_node({:unary_op, :negate, expr}) do
    expr_fn = compile_node(expr)

    fn event ->
      case expr_fn.(event) do
        n when is_number(n) -> -n
        _ -> nil
      end
    end
  end

  defp compile_node({:regex_match, expr, pattern}) do
    expr_fn = compile_node(expr)
    pattern_fn = compile_node(pattern)

    fn event ->
      string = expr_fn.(event)
      pat = pattern_fn.(event)
      Functions.match(string, pat)
    end
  end

  defp compile_node({:string_op, :contains, left, right}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> Functions.contains(left_fn.(event), right_fn.(event)) end
  end

  defp compile_node({:string_op, :starts_with, left, right}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> Functions.starts_with(left_fn.(event), right_fn.(event)) end
  end

  defp compile_node({:string_op, :ends_with, left, right}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> Functions.ends_with(left_fn.(event), right_fn.(event)) end
  end

  # Function calls
  defp compile_node({:call, name, _args}) when name not in @known_functions do
    raise ArgumentError, "unknown function: #{name}"
  end

  defp compile_node({:call, "now", []}) do
    fn _event -> Functions.now() end
  end

  defp compile_node({:call, "exists", [arg]}) do
    case arg do
      {:field, path} ->
        fn event -> Functions.exists(event, path) end

      _ ->
        arg_fn = compile_node(arg)
        fn event -> arg_fn.(event) != nil end
    end
  end

  defp compile_node({:call, "length", [arg]}) do
    arg_fn = compile_node(arg)
    fn event -> Functions.length(arg_fn.(event)) end
  end

  defp compile_node({:call, "downcase", [arg]}) do
    arg_fn = compile_node(arg)
    fn event -> Functions.downcase(arg_fn.(event)) end
  end

  defp compile_node({:call, "upcase", [arg]}) do
    arg_fn = compile_node(arg)
    fn event -> Functions.upcase(arg_fn.(event)) end
  end

  defp compile_node({:call, "to_int", [arg]}) do
    arg_fn = compile_node(arg)
    fn event -> Functions.to_int(arg_fn.(event)) end
  end

  defp compile_node({:call, "to_float", [arg]}) do
    arg_fn = compile_node(arg)
    fn event -> Functions.to_float(arg_fn.(event)) end
  end

  defp compile_node({:call, "to_string", [arg]}) do
    arg_fn = compile_node(arg)
    fn event -> Functions.to_string(arg_fn.(event)) end
  end

  defp compile_node({:call, "contains", [left, right]}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> Functions.contains(left_fn.(event), right_fn.(event)) end
  end

  defp compile_node({:call, "starts_with", [left, right]}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> Functions.starts_with(left_fn.(event), right_fn.(event)) end
  end

  defp compile_node({:call, "ends_with", [left, right]}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> Functions.ends_with(left_fn.(event), right_fn.(event)) end
  end

  defp compile_node({:call, "match", [left, right]}) do
    left_fn = compile_node(left)
    right_fn = compile_node(right)
    fn event -> Functions.match(left_fn.(event), right_fn.(event)) end
  end

  defp compile_node({:call, name, args}) do
    raise ArgumentError, "wrong number of arguments for #{name}/#{Kernel.length(args)}"
  end

  # --- Helpers ---

  defp truthy?(nil), do: false
  defp truthy?(false), do: false
  defp truthy?(0), do: false
  defp truthy?(""), do: false
  defp truthy?(_), do: true

  defp apply_comparison(:==, l, r), do: l == r
  defp apply_comparison(:!=, l, r), do: l != r
  defp apply_comparison(:>, l, r) when is_number(l) and is_number(r), do: l > r
  defp apply_comparison(:>, l, r) when is_binary(l) and is_binary(r), do: l > r
  defp apply_comparison(:<, l, r) when is_number(l) and is_number(r), do: l < r
  defp apply_comparison(:<, l, r) when is_binary(l) and is_binary(r), do: l < r
  defp apply_comparison(:>=, l, r) when is_number(l) and is_number(r), do: l >= r
  defp apply_comparison(:>=, l, r) when is_binary(l) and is_binary(r), do: l >= r
  defp apply_comparison(:<=, l, r) when is_number(l) and is_number(r), do: l <= r
  defp apply_comparison(:<=, l, r) when is_binary(l) and is_binary(r), do: l <= r
  defp apply_comparison(_op, _l, _r), do: false

  defp apply_arithmetic(:+, l, r) when is_number(l) and is_number(r), do: l + r
  defp apply_arithmetic(:+, l, r) when is_binary(l) and is_binary(r), do: l <> r
  defp apply_arithmetic(:-, l, r) when is_number(l) and is_number(r), do: l - r
  defp apply_arithmetic(:*, l, r) when is_number(l) and is_number(r), do: l * r
  defp apply_arithmetic(:/, _l, 0), do: nil
  defp apply_arithmetic(:/, _l, +0.0), do: nil
  defp apply_arithmetic(:/, l, r) when is_number(l) and is_number(r), do: l / r
  defp apply_arithmetic(_op, _l, _r), do: nil
end
