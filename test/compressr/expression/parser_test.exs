defmodule Compressr.Expression.ParserTest do
  use ExUnit.Case, async: true

  alias Compressr.Expression.Parser

  describe "literals" do
    test "integer" do
      assert {:ok, {:literal, 42}} = Parser.parse("42")
    end

    test "negative integer via unary minus" do
      assert {:ok, {:unary_op, :negate, {:literal, 42}}} = Parser.parse("-42")
    end

    test "float" do
      assert {:ok, {:literal, 3.14}} = Parser.parse("3.14")
    end

    test "string" do
      assert {:ok, {:literal, "hello"}} = Parser.parse(~s["hello"])
    end

    test "string with escaped quote" do
      assert {:ok, {:literal, ~s[say "hi"]}} = Parser.parse(~s["say \\"hi\\""])
    end

    test "boolean true" do
      assert {:ok, {:literal, true}} = Parser.parse("true")
    end

    test "boolean false" do
      assert {:ok, {:literal, false}} = Parser.parse("false")
    end

    test "null" do
      assert {:ok, {:literal, nil}} = Parser.parse("null")
    end
  end

  describe "field access" do
    test "simple field" do
      assert {:ok, {:field, ["severity"]}} = Parser.parse(".severity")
    end

    test "nested field" do
      assert {:ok, {:field, ["request", "path"]}} = Parser.parse(".request.path")
    end

    test "deeply nested field" do
      assert {:ok, {:field, ["a", "b", "c"]}} = Parser.parse(".a.b.c")
    end

    test "bare identifier as field" do
      assert {:ok, {:field, ["severity"]}} = Parser.parse("severity")
    end
  end

  describe "comparisons" do
    test "equals" do
      assert {:ok, {:binary_op, :==, {:field, ["x"]}, {:literal, 1}}} =
               Parser.parse(".x == 1")
    end

    test "not equals" do
      assert {:ok, {:binary_op, :!=, {:field, ["x"]}, {:literal, 1}}} =
               Parser.parse(".x != 1")
    end

    test "greater than" do
      assert {:ok, {:binary_op, :>, {:field, ["severity"]}, {:literal, 3}}} =
               Parser.parse(".severity > 3")
    end

    test "less than" do
      assert {:ok, {:binary_op, :<, {:field, ["x"]}, {:literal, 10}}} =
               Parser.parse(".x < 10")
    end

    test "greater than or equal" do
      assert {:ok, {:binary_op, :>=, {:field, ["x"]}, {:literal, 5}}} =
               Parser.parse(".x >= 5")
    end

    test "less than or equal" do
      assert {:ok, {:binary_op, :<=, {:field, ["x"]}, {:literal, 5}}} =
               Parser.parse(".x <= 5")
    end

    test "string comparison" do
      assert {:ok, {:binary_op, :==, {:field, ["source"]}, {:literal, "cloudtrail"}}} =
               Parser.parse(~s[.source == "cloudtrail"])
    end
  end

  describe "boolean operators" do
    test "and" do
      assert {:ok,
              {:binary_op, :and, {:binary_op, :==, {:field, ["a"]}, {:literal, 1}},
               {:binary_op, :==, {:field, ["b"]}, {:literal, 2}}}} =
               Parser.parse(".a == 1 and .b == 2")
    end

    test "or" do
      assert {:ok,
              {:binary_op, :or, {:binary_op, :==, {:field, ["a"]}, {:literal, 1}},
               {:binary_op, :==, {:field, ["b"]}, {:literal, 2}}}} =
               Parser.parse(".a == 1 or .b == 2")
    end

    test "not" do
      assert {:ok, {:unary_op, :not, {:field, ["active"]}}} =
               Parser.parse("not .active")
    end

    test "precedence: and binds tighter than or" do
      # a or b and c  =>  a or (b and c)
      {:ok, ast} = Parser.parse(".a or .b and .c")

      assert {:binary_op, :or, {:field, ["a"]},
              {:binary_op, :and, {:field, ["b"]}, {:field, ["c"]}}} = ast
    end
  end

  describe "arithmetic" do
    test "addition" do
      assert {:ok, {:binary_op, :+, {:field, ["a"]}, {:field, ["b"]}}} =
               Parser.parse(".a + .b")
    end

    test "subtraction" do
      assert {:ok, {:binary_op, :-, {:field, ["a"]}, {:literal, 1}}} =
               Parser.parse(".a - 1")
    end

    test "multiplication" do
      assert {:ok, {:binary_op, :*, {:field, ["a"]}, {:literal, 2}}} =
               Parser.parse(".a * 2")
    end

    test "division" do
      assert {:ok, {:binary_op, :/, {:field, ["a"]}, {:literal, 2}}} =
               Parser.parse(".a / 2")
    end

    test "precedence: * before +" do
      # a + b * c  =>  a + (b * c)
      {:ok, ast} = Parser.parse(".a + .b * .c")

      assert {:binary_op, :+, {:field, ["a"]}, {:binary_op, :*, {:field, ["b"]}, {:field, ["c"]}}} =
               ast
    end
  end

  describe "regex match" do
    test "=~ operator" do
      assert {:ok, {:regex_match, {:field, ["message"]}, {:literal, "error"}}} =
               Parser.parse(~s[.message =~ "error"])
    end
  end

  describe "string operators" do
    test "contains" do
      assert {:ok, {:string_op, :contains, {:field, ["msg"]}, {:literal, "err"}}} =
               Parser.parse(~s[.msg contains "err"])
    end

    test "starts_with" do
      assert {:ok, {:string_op, :starts_with, {:field, ["path"]}, {:literal, "/api"}}} =
               Parser.parse(~s[.path starts_with "/api"])
    end

    test "ends_with" do
      assert {:ok, {:string_op, :ends_with, {:field, ["file"]}, {:literal, ".log"}}} =
               Parser.parse(~s[.file ends_with ".log"])
    end
  end

  describe "function calls" do
    test "no-arg function" do
      assert {:ok, {:call, "now", []}} = Parser.parse("now()")
    end

    test "single-arg function with field" do
      assert {:ok, {:call, "exists", [{:field, ["user_id"]}]}} =
               Parser.parse("exists(.user_id)")
    end

    test "single-arg function with literal" do
      assert {:ok, {:call, "length", [{:literal, "hello"}]}} =
               Parser.parse(~s[length("hello")])
    end

    test "two-arg function" do
      assert {:ok, {:call, "contains", [{:field, ["msg"]}, {:literal, "error"}]}} =
               Parser.parse(~s[contains(.msg, "error")])
    end

    test "nested function in expression" do
      {:ok, ast} = Parser.parse("length(.message) > 100")

      assert {:binary_op, :>, {:call, "length", [{:field, ["message"]}]}, {:literal, 100}} = ast
    end
  end

  describe "parentheses" do
    test "grouping overrides precedence" do
      # (a + b) * c  =>  (* (+ a b) c)
      {:ok, ast} = Parser.parse("(.a + .b) * .c")

      assert {:binary_op, :*, {:binary_op, :+, {:field, ["a"]}, {:field, ["b"]}}, {:field, ["c"]}} =
               ast
    end

    test "nested parentheses" do
      {:ok, _ast} = Parser.parse("((.a + .b) * .c)")
    end
  end

  describe "complex expressions" do
    test "mixed boolean and comparison" do
      {:ok, ast} = Parser.parse(~s[.source == "cloudtrail" and .severity > 3])

      assert {:binary_op, :and, {:binary_op, :==, {:field, ["source"]}, {:literal, "cloudtrail"}},
              {:binary_op, :>, {:field, ["severity"]}, {:literal, 3}}} = ast
    end

    test "arithmetic in comparison" do
      {:ok, ast} = Parser.parse(".bytes_in + .bytes_out > 1000")

      assert {:binary_op, :>, {:binary_op, :+, {:field, ["bytes_in"]}, {:field, ["bytes_out"]}},
              {:literal, 1000}} = ast
    end
  end

  describe "error cases" do
    test "empty expression" do
      assert {:error, "empty expression"} = Parser.parse("")
    end

    test "unterminated string" do
      assert {:error, "unterminated string literal"} = Parser.parse(~s["hello])
    end

    test "unexpected character" do
      assert {:error, "unexpected character: @"} = Parser.parse("@field")
    end

    test "missing closing paren" do
      assert {:error, _} = Parser.parse("(.a + .b")
    end

    test "trailing tokens" do
      assert {:error, _} = Parser.parse(".a .b")
    end

    test "empty field after dot" do
      assert {:error, _} = Parser.parse(". ")
    end
  end
end
