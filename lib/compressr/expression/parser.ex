defmodule Compressr.Expression.Parser do
  @moduledoc """
  Recursive descent parser for the compressr expression language.

  Parses expression strings into an AST represented as nested tuples.

  ## AST Node Types

      {:literal, value}                      — literal value (string, int, float, bool, nil)
      {:field, [path_segments]}              — field access (e.g., .severity or .request.path)
      {:binary_op, op, left, right}          — binary operation (+, -, *, /, ==, !=, >, <, >=, <=, and, or)
      {:unary_op, :not, expr}                — unary not
      {:regex_match, expr, pattern}          — =~ regex match
      {:call, name, args}                    — function call
      {:string_op, op, expr, arg}            — contains, starts_with, ends_with

  ## Grammar (precedence low to high)

      expression     = or_expr
      or_expr        = and_expr ("or" and_expr)*
      and_expr       = not_expr ("and" not_expr)*
      not_expr       = "not" not_expr | comparison
      comparison     = addition (("==" | "!=" | ">=" | "<=" | ">" | "<" | "=~") addition)*
                     | addition ("contains" | "starts_with" | "ends_with") addition
      addition       = multiplication (("+" | "-") multiplication)*
      multiplication = unary (("*" | "/") unary)*
      unary          = "-" unary | primary
      primary        = literal | field | function_call | "(" expression ")"
  """

  @type token :: {atom(), any()} | {atom()}

  # --- Public API ---

  @doc "Parses an expression string into an AST. Returns {:ok, ast} or {:error, reason}."
  @spec parse(String.t()) :: {:ok, any()} | {:error, String.t()}
  def parse(input) when is_binary(input) do
    input = String.trim(input)

    if input == "" do
      {:error, "empty expression"}
    else
      case tokenize(input) do
        {:ok, tokens} ->
          case parse_expression(tokens) do
            {:ok, ast, []} ->
              {:ok, ast}

            {:ok, _ast, remaining} ->
              {:error, "unexpected tokens after expression: #{inspect_tokens(remaining)}"}

            {:error, reason} ->
              {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # --- Tokenizer ---

  @spec tokenize(String.t()) :: {:ok, [token()]} | {:error, String.t()}
  defp tokenize(input) do
    tokenize(input, [])
  end

  defp tokenize(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  # Whitespace
  defp tokenize(<<c, rest::binary>>, acc) when c in [?\s, ?\t, ?\n, ?\r] do
    tokenize(rest, acc)
  end

  # Two-character operators
  defp tokenize(<<"==", rest::binary>>, acc), do: tokenize(rest, [{:op, :==} | acc])
  defp tokenize(<<"!=", rest::binary>>, acc), do: tokenize(rest, [{:op, :!=} | acc])
  defp tokenize(<<">=", rest::binary>>, acc), do: tokenize(rest, [{:op, :>=} | acc])
  defp tokenize(<<"<=", rest::binary>>, acc), do: tokenize(rest, [{:op, :<=} | acc])
  defp tokenize(<<"=~", rest::binary>>, acc), do: tokenize(rest, [{:op, :=~} | acc])

  # Single-character operators
  defp tokenize(<<">", rest::binary>>, acc), do: tokenize(rest, [{:op, :>} | acc])
  defp tokenize(<<"<", rest::binary>>, acc), do: tokenize(rest, [{:op, :<} | acc])
  defp tokenize(<<"+", rest::binary>>, acc), do: tokenize(rest, [{:op, :+} | acc])
  defp tokenize(<<"-", rest::binary>>, acc), do: tokenize(rest, [{:op, :-} | acc])
  defp tokenize(<<"*", rest::binary>>, acc), do: tokenize(rest, [{:op, :*} | acc])
  defp tokenize(<<"/", rest::binary>>, acc), do: tokenize(rest, [{:op, :/} | acc])

  # Parentheses and comma
  defp tokenize(<<"(", rest::binary>>, acc), do: tokenize(rest, [{:lparen} | acc])
  defp tokenize(<<")", rest::binary>>, acc), do: tokenize(rest, [{:rparen} | acc])
  defp tokenize(<<",", rest::binary>>, acc), do: tokenize(rest, [{:comma} | acc])

  # Field access starting with dot
  defp tokenize(<<".", rest::binary>>, acc) do
    case read_field_path(rest, []) do
      {:ok, path, remaining} -> tokenize(remaining, [{:field, path} | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  # String literals
  defp tokenize(<<"\"", rest::binary>>, acc) do
    case read_string(rest, []) do
      {:ok, string, remaining} -> tokenize(remaining, [{:string, string} | acc])
      {:error, reason} -> {:error, reason}
    end
  end

  # Numbers
  defp tokenize(<<c, _rest::binary>> = input, acc) when c in ?0..?9 do
    {num_token, remaining} = read_number(input)
    tokenize(remaining, [num_token | acc])
  end

  # Identifiers and keywords
  defp tokenize(<<c, _rest::binary>> = input, acc) when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {ident, remaining} = read_identifier(input)

    token =
      case ident do
        "true" -> {:bool, true}
        "false" -> {:bool, false}
        "null" -> {:null}
        "nil" -> {:null}
        "and" -> {:op, :and}
        "or" -> {:op, :or}
        "not" -> {:op, :not}
        "contains" -> {:op, :contains}
        "starts_with" -> {:op, :starts_with}
        "ends_with" -> {:op, :ends_with}
        _ -> {:ident, ident}
      end

    tokenize(remaining, [token | acc])
  end

  defp tokenize(<<c, _rest::binary>>, _acc) do
    {:error, "unexpected character: #{<<c>>}"}
  end

  defp read_field_path(input, segments) do
    case read_identifier_chars(input) do
      {"", _rest} ->
        {:error, "expected field name after '.'"}

      {name, <<".", rest::binary>>} ->
        read_field_path(rest, [name | segments])

      {name, rest} ->
        {:ok, Enum.reverse([name | segments]), rest}
    end
  end

  defp read_identifier_chars(input), do: read_identifier_chars(input, [])

  defp read_identifier_chars(<<c, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    read_identifier_chars(rest, [c | acc])
  end

  defp read_identifier_chars(rest, acc) do
    {acc |> Enum.reverse() |> List.to_string(), rest}
  end

  defp read_string(<<"\\\"", rest::binary>>, acc), do: read_string(rest, [?" | acc])
  defp read_string(<<"\\\\", rest::binary>>, acc), do: read_string(rest, [?\\ | acc])
  defp read_string(<<"\\n", rest::binary>>, acc), do: read_string(rest, [?\n | acc])
  defp read_string(<<"\\t", rest::binary>>, acc), do: read_string(rest, [?\t | acc])

  defp read_string(<<"\"", rest::binary>>, acc),
    do: {:ok, acc |> Enum.reverse() |> List.to_string(), rest}

  defp read_string(<<c, rest::binary>>, acc), do: read_string(rest, [c | acc])
  defp read_string(<<>>, _acc), do: {:error, "unterminated string literal"}

  defp read_number(input), do: read_number(input, [], false)

  defp read_number(<<c, rest::binary>>, acc, is_float) when c in ?0..?9 do
    read_number(rest, [c | acc], is_float)
  end

  defp read_number(<<".", c, rest::binary>>, acc, false) when c in ?0..?9 do
    read_number(rest, [c, ?. | acc], true)
  end

  defp read_number(rest, acc, is_float) do
    str = acc |> Enum.reverse() |> List.to_string()

    token =
      if is_float do
        {:float, String.to_float(str)}
      else
        {:int, String.to_integer(str)}
      end

    {token, rest}
  end

  defp read_identifier(input), do: read_identifier(input, [])

  defp read_identifier(<<c, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_ do
    read_identifier(rest, [c | acc])
  end

  defp read_identifier(rest, acc) do
    {acc |> Enum.reverse() |> List.to_string(), rest}
  end

  # --- Parser ---

  defp parse_expression(tokens), do: parse_or(tokens)

  defp parse_or(tokens) do
    with {:ok, left, rest} <- parse_and(tokens) do
      parse_or_rest(left, rest)
    end
  end

  defp parse_or_rest(left, [{:op, :or} | rest]) do
    with {:ok, right, rest2} <- parse_and(rest) do
      parse_or_rest({:binary_op, :or, left, right}, rest2)
    end
  end

  defp parse_or_rest(left, rest), do: {:ok, left, rest}

  defp parse_and(tokens) do
    with {:ok, left, rest} <- parse_not(tokens) do
      parse_and_rest(left, rest)
    end
  end

  defp parse_and_rest(left, [{:op, :and} | rest]) do
    with {:ok, right, rest2} <- parse_not(rest) do
      parse_and_rest({:binary_op, :and, left, right}, rest2)
    end
  end

  defp parse_and_rest(left, rest), do: {:ok, left, rest}

  defp parse_not([{:op, :not} | rest]) do
    with {:ok, expr, rest2} <- parse_not(rest) do
      {:ok, {:unary_op, :not, expr}, rest2}
    end
  end

  defp parse_not(tokens), do: parse_comparison(tokens)

  defp parse_comparison(tokens) do
    with {:ok, left, rest} <- parse_addition(tokens) do
      case rest do
        [{:op, op} | rest2] when op in [:==, :!=, :>, :<, :>=, :<=] ->
          with {:ok, right, rest3} <- parse_addition(rest2) do
            {:ok, {:binary_op, op, left, right}, rest3}
          end

        [{:op, :=~} | rest2] ->
          with {:ok, right, rest3} <- parse_addition(rest2) do
            {:ok, {:regex_match, left, right}, rest3}
          end

        [{:op, op} | rest2] when op in [:contains, :starts_with, :ends_with] ->
          with {:ok, right, rest3} <- parse_addition(rest2) do
            {:ok, {:string_op, op, left, right}, rest3}
          end

        _ ->
          {:ok, left, rest}
      end
    end
  end

  defp parse_addition(tokens) do
    with {:ok, left, rest} <- parse_multiplication(tokens) do
      parse_addition_rest(left, rest)
    end
  end

  defp parse_addition_rest(left, [{:op, op} | rest]) when op in [:+, :-] do
    with {:ok, right, rest2} <- parse_multiplication(rest) do
      parse_addition_rest({:binary_op, op, left, right}, rest2)
    end
  end

  defp parse_addition_rest(left, rest), do: {:ok, left, rest}

  defp parse_multiplication(tokens) do
    with {:ok, left, rest} <- parse_unary(tokens) do
      parse_multiplication_rest(left, rest)
    end
  end

  defp parse_multiplication_rest(left, [{:op, op} | rest]) when op in [:*, :/] do
    with {:ok, right, rest2} <- parse_unary(rest) do
      parse_multiplication_rest({:binary_op, op, left, right}, rest2)
    end
  end

  defp parse_multiplication_rest(left, rest), do: {:ok, left, rest}

  defp parse_unary([{:op, :-} | rest]) do
    with {:ok, expr, rest2} <- parse_unary(rest) do
      {:ok, {:unary_op, :negate, expr}, rest2}
    end
  end

  defp parse_unary(tokens), do: parse_primary(tokens)

  # Parenthesized expression
  defp parse_primary([{:lparen} | rest]) do
    with {:ok, expr, rest2} <- parse_expression(rest) do
      case rest2 do
        [{:rparen} | rest3] -> {:ok, expr, rest3}
        _ -> {:error, "expected closing parenthesis"}
      end
    end
  end

  # Literals
  defp parse_primary([{:string, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:int, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:float, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:bool, value} | rest]), do: {:ok, {:literal, value}, rest}
  defp parse_primary([{:null} | rest]), do: {:ok, {:literal, nil}, rest}

  # Field access
  defp parse_primary([{:field, path} | rest]), do: {:ok, {:field, path}, rest}

  # Function call: ident(args...)
  defp parse_primary([{:ident, name}, {:lparen} | rest]) do
    case parse_args(rest) do
      {:ok, args, rest2} -> {:ok, {:call, name, args}, rest2}
      {:error, reason} -> {:error, reason}
    end
  end

  # Keywords used as function calls: contains(.msg, "err"), starts_with(...), ends_with(...)
  defp parse_primary([{:op, op}, {:lparen} | rest])
       when op in [:contains, :starts_with, :ends_with] do
    name = Atom.to_string(op)

    case parse_args(rest) do
      {:ok, args, rest2} -> {:ok, {:call, name, args}, rest2}
      {:error, reason} -> {:error, reason}
    end
  end

  # Bare identifier treated as field name (no leading dot)
  defp parse_primary([{:ident, name} | rest]), do: {:ok, {:field, [name]}, rest}

  defp parse_primary([]) do
    {:error, "unexpected end of expression"}
  end

  defp parse_primary([token | _]) do
    {:error, "unexpected token: #{inspect_token(token)}"}
  end

  defp parse_args([{:rparen} | rest]), do: {:ok, [], rest}

  defp parse_args(tokens) do
    with {:ok, expr, rest} <- parse_expression(tokens) do
      parse_args_rest([expr], rest)
    end
  end

  defp parse_args_rest(acc, [{:comma} | rest]) do
    with {:ok, expr, rest2} <- parse_expression(rest) do
      parse_args_rest([expr | acc], rest2)
    end
  end

  defp parse_args_rest(acc, [{:rparen} | rest]) do
    {:ok, Enum.reverse(acc), rest}
  end

  defp parse_args_rest(_acc, _rest) do
    {:error, "expected ',' or ')' in function arguments"}
  end

  defp inspect_token({:op, op}), do: Atom.to_string(op)
  defp inspect_token({:ident, name}), do: name
  defp inspect_token({:field, path}), do: "." <> Enum.join(path, ".")
  defp inspect_token({:string, s}), do: ~s("#{s}")
  defp inspect_token({:int, n}), do: Integer.to_string(n)
  defp inspect_token({:float, f}), do: Float.to_string(f)
  defp inspect_token({:bool, b}), do: Atom.to_string(b)
  defp inspect_token({:null}), do: "null"
  defp inspect_token({:lparen}), do: "("
  defp inspect_token({:rparen}), do: ")"
  defp inspect_token({:comma}), do: ","
  defp inspect_token(other), do: inspect(other)

  defp inspect_tokens(tokens), do: tokens |> Enum.map(&inspect_token/1) |> Enum.join(" ")
end
