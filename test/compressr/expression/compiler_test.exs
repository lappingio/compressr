defmodule Compressr.Expression.CompilerTest do
  use ExUnit.Case, async: true

  alias Compressr.Expression.Compiler

  defp compile_and_eval(ast, event \\ %{}) do
    {:ok, fun} = Compiler.compile(ast)
    fun.(event)
  end

  describe "literals" do
    test "integer" do
      assert compile_and_eval({:literal, 42}) == 42
    end

    test "string" do
      assert compile_and_eval({:literal, "hello"}) == "hello"
    end

    test "boolean" do
      assert compile_and_eval({:literal, true}) == true
    end

    test "nil" do
      assert compile_and_eval({:literal, nil}) == nil
    end
  end

  describe "field access" do
    test "existing field" do
      assert compile_and_eval({:field, ["name"]}, %{"name" => "alice"}) == "alice"
    end

    test "missing field returns nil" do
      assert compile_and_eval({:field, ["name"]}, %{}) == nil
    end

    test "nested field" do
      event = %{"request" => %{"path" => "/api"}}
      assert compile_and_eval({:field, ["request", "path"]}, event) == "/api"
    end
  end

  describe "comparisons" do
    test "equal" do
      ast = {:binary_op, :==, {:field, ["x"]}, {:literal, 5}}
      assert compile_and_eval(ast, %{"x" => 5}) == true
      assert compile_and_eval(ast, %{"x" => 3}) == false
    end

    test "not equal" do
      ast = {:binary_op, :!=, {:field, ["x"]}, {:literal, 5}}
      assert compile_and_eval(ast, %{"x" => 3}) == true
    end

    test "greater than" do
      ast = {:binary_op, :>, {:field, ["x"]}, {:literal, 3}}
      assert compile_and_eval(ast, %{"x" => 5}) == true
      assert compile_and_eval(ast, %{"x" => 2}) == false
    end

    test "less than" do
      ast = {:binary_op, :<, {:field, ["x"]}, {:literal, 3}}
      assert compile_and_eval(ast, %{"x" => 1}) == true
    end

    test "comparison with nil returns false" do
      ast = {:binary_op, :>, {:field, ["x"]}, {:literal, 3}}
      assert compile_and_eval(ast, %{}) == false
    end
  end

  describe "boolean operators" do
    test "and - both true" do
      ast = {:binary_op, :and, {:literal, true}, {:literal, true}}
      assert compile_and_eval(ast) == true
    end

    test "and - one false" do
      ast = {:binary_op, :and, {:literal, true}, {:literal, false}}
      assert compile_and_eval(ast) == false
    end

    test "or - one true" do
      ast = {:binary_op, :or, {:literal, false}, {:literal, true}}
      assert compile_and_eval(ast) == true
    end

    test "not" do
      ast = {:unary_op, :not, {:literal, true}}
      assert compile_and_eval(ast) == false
    end

    test "not nil is truthy" do
      ast = {:unary_op, :not, {:literal, nil}}
      assert compile_and_eval(ast) == true
    end
  end

  describe "arithmetic" do
    test "addition" do
      ast = {:binary_op, :+, {:literal, 2}, {:literal, 3}}
      assert compile_and_eval(ast) == 5
    end

    test "subtraction" do
      ast = {:binary_op, :-, {:literal, 10}, {:literal, 3}}
      assert compile_and_eval(ast) == 7
    end

    test "multiplication" do
      ast = {:binary_op, :*, {:literal, 4}, {:literal, 5}}
      assert compile_and_eval(ast) == 20
    end

    test "division" do
      ast = {:binary_op, :/, {:literal, 10}, {:literal, 2}}
      assert compile_and_eval(ast) == 5.0
    end

    test "division by zero returns nil" do
      ast = {:binary_op, :/, {:literal, 10}, {:literal, 0}}
      assert compile_and_eval(ast) == nil
    end

    test "string concatenation with +" do
      ast = {:binary_op, :+, {:literal, "hello "}, {:literal, "world"}}
      assert compile_and_eval(ast) == "hello world"
    end

    test "arithmetic with nil returns nil" do
      ast = {:binary_op, :+, {:field, ["x"]}, {:literal, 1}}
      assert compile_and_eval(ast, %{}) == nil
    end

    test "negation" do
      ast = {:unary_op, :negate, {:literal, 5}}
      assert compile_and_eval(ast) == -5
    end
  end

  describe "regex match" do
    test "matching" do
      ast = {:regex_match, {:field, ["msg"]}, {:literal, "err"}}
      assert compile_and_eval(ast, %{"msg" => "error occurred"}) == true
    end

    test "non-matching" do
      ast = {:regex_match, {:field, ["msg"]}, {:literal, "err"}}
      assert compile_and_eval(ast, %{"msg" => "all good"}) == false
    end
  end

  describe "string operations" do
    test "contains" do
      ast = {:string_op, :contains, {:field, ["msg"]}, {:literal, "err"}}
      assert compile_and_eval(ast, %{"msg" => "error here"}) == true
    end

    test "starts_with" do
      ast = {:string_op, :starts_with, {:field, ["path"]}, {:literal, "/api"}}
      assert compile_and_eval(ast, %{"path" => "/api/users"}) == true
    end

    test "ends_with" do
      ast = {:string_op, :ends_with, {:field, ["file"]}, {:literal, ".log"}}
      assert compile_and_eval(ast, %{"file" => "app.log"}) == true
    end
  end

  describe "function calls" do
    test "exists with present field" do
      ast = {:call, "exists", [{:field, ["name"]}]}
      assert compile_and_eval(ast, %{"name" => "alice"}) == true
    end

    test "exists with missing field" do
      ast = {:call, "exists", [{:field, ["name"]}]}
      assert compile_and_eval(ast, %{}) == false
    end

    test "length" do
      ast = {:call, "length", [{:field, ["items"]}]}
      assert compile_and_eval(ast, %{"items" => [1, 2, 3]}) == 3
    end

    test "downcase" do
      ast = {:call, "downcase", [{:field, ["name"]}]}
      assert compile_and_eval(ast, %{"name" => "HELLO"}) == "hello"
    end

    test "upcase" do
      ast = {:call, "upcase", [{:field, ["name"]}]}
      assert compile_and_eval(ast, %{"name" => "hello"}) == "HELLO"
    end

    test "to_int" do
      ast = {:call, "to_int", [{:field, ["val"]}]}
      assert compile_and_eval(ast, %{"val" => "42"}) == 42
    end

    test "now returns timestamp" do
      ast = {:call, "now", []}
      result = compile_and_eval(ast)
      assert is_integer(result)
      assert result > 1_700_000_000
    end

    test "unknown function raises" do
      assert_raise ArgumentError, ~r/unknown function/, fn ->
        Compiler.compile!({:call, "unknown_fn", []})
      end
    end

    test "wrong arity raises" do
      assert_raise ArgumentError, ~r/wrong number of arguments/, fn ->
        Compiler.compile!({:call, "length", []})
      end
    end
  end
end
