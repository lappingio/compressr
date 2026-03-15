defmodule Compressr.ExpressionTest do
  use ExUnit.Case, async: true

  alias Compressr.Expression

  describe "compile and evaluate — simple comparisons" do
    test ".severity > 3" do
      {:ok, fun} = Expression.compile(".severity > 3")
      assert Expression.evaluate(fun, %{"severity" => 5}) == true
      assert Expression.evaluate(fun, %{"severity" => 2}) == false
    end

    test ".severity == 3" do
      {:ok, fun} = Expression.compile(".severity == 3")
      assert Expression.evaluate(fun, %{"severity" => 3}) == true
      assert Expression.evaluate(fun, %{"severity" => 4}) == false
    end

    test ".count != 0" do
      {:ok, fun} = Expression.compile(".count != 0")
      assert Expression.evaluate(fun, %{"count" => 5}) == true
      assert Expression.evaluate(fun, %{"count" => 0}) == false
    end

    test ".x >= 10" do
      {:ok, fun} = Expression.compile(".x >= 10")
      assert Expression.evaluate(fun, %{"x" => 10}) == true
      assert Expression.evaluate(fun, %{"x" => 9}) == false
    end

    test ".x <= 10" do
      {:ok, fun} = Expression.compile(".x <= 10")
      assert Expression.evaluate(fun, %{"x" => 10}) == true
      assert Expression.evaluate(fun, %{"x" => 11}) == false
    end
  end

  describe "compile and evaluate — boolean logic" do
    test "and" do
      {:ok, fun} =
        Expression.compile(~s[.source == "cloudtrail" and .severity > 3])

      assert Expression.evaluate(fun, %{"source" => "cloudtrail", "severity" => 5}) == true
      assert Expression.evaluate(fun, %{"source" => "cloudtrail", "severity" => 1}) == false
      assert Expression.evaluate(fun, %{"source" => "other", "severity" => 5}) == false
    end

    test "or" do
      {:ok, fun} =
        Expression.compile(~s[.severity > 7 or .source == "security"])

      assert Expression.evaluate(fun, %{"severity" => 8, "source" => "app"}) == true
      assert Expression.evaluate(fun, %{"severity" => 2, "source" => "security"}) == true
      assert Expression.evaluate(fun, %{"severity" => 2, "source" => "app"}) == false
    end

    test "not" do
      {:ok, fun} = Expression.compile("not .disabled")
      assert Expression.evaluate(fun, %{"disabled" => false}) == true
      assert Expression.evaluate(fun, %{"disabled" => true}) == false
      assert Expression.evaluate(fun, %{}) == true
    end

    test "complex boolean: (a or b) and c" do
      {:ok, fun} =
        Expression.compile(~s[(.severity > 5 or .source == "security") and .active == true])

      assert Expression.evaluate(fun, %{
               "severity" => 8,
               "source" => "app",
               "active" => true
             }) == true

      assert Expression.evaluate(fun, %{
               "severity" => 8,
               "source" => "app",
               "active" => false
             }) == false
    end
  end

  describe "compile and evaluate — string matching" do
    test "=~ regex match" do
      {:ok, fun} = Expression.compile(~s[.message =~ "error"])
      assert Expression.evaluate(fun, %{"message" => "an error occurred"}) == true
      assert Expression.evaluate(fun, %{"message" => "all good"}) == false
    end

    test "=~ with regex pattern" do
      {:ok, fun} = Expression.compile(~s[.message =~ "\\\\d{3}"])
      assert Expression.evaluate(fun, %{"message" => "code 404 found"}) == true
      assert Expression.evaluate(fun, %{"message" => "no numbers"}) == false
    end

    test "contains" do
      {:ok, fun} = Expression.compile(~s[.message contains "warning"])
      assert Expression.evaluate(fun, %{"message" => "this is a warning message"}) == true
      assert Expression.evaluate(fun, %{"message" => "all clear"}) == false
    end

    test "starts_with" do
      {:ok, fun} = Expression.compile(~s[.path starts_with "/api"])
      assert Expression.evaluate(fun, %{"path" => "/api/users"}) == true
      assert Expression.evaluate(fun, %{"path" => "/web/home"}) == false
    end

    test "ends_with" do
      {:ok, fun} = Expression.compile(~s[.filename ends_with ".log"])
      assert Expression.evaluate(fun, %{"filename" => "app.log"}) == true
      assert Expression.evaluate(fun, %{"filename" => "app.txt"}) == false
    end
  end

  describe "compile and evaluate — function calls" do
    test "exists with present field" do
      {:ok, fun} = Expression.compile("exists(.user_id)")
      assert Expression.evaluate(fun, %{"user_id" => "u123"}) == true
    end

    test "exists with missing field" do
      {:ok, fun} = Expression.compile("exists(.user_id)")
      assert Expression.evaluate(fun, %{}) == false
    end

    test "exists with nil field" do
      {:ok, fun} = Expression.compile("exists(.user_id)")
      assert Expression.evaluate(fun, %{"user_id" => nil}) == false
    end

    test "length of string > threshold" do
      {:ok, fun} = Expression.compile("length(.message) > 100")
      long_msg = String.duplicate("x", 150)
      short_msg = "short"
      assert Expression.evaluate(fun, %{"message" => long_msg}) == true
      assert Expression.evaluate(fun, %{"message" => short_msg}) == false
    end

    test "length of list" do
      {:ok, fun} = Expression.compile("length(.tags) > 2")
      assert Expression.evaluate(fun, %{"tags" => ["a", "b", "c"]}) == true
      assert Expression.evaluate(fun, %{"tags" => ["a"]}) == false
    end

    test "downcase" do
      {:ok, fun} = Expression.compile(~s[downcase(.level) == "error"])
      assert Expression.evaluate(fun, %{"level" => "ERROR"}) == true
      assert Expression.evaluate(fun, %{"level" => "info"}) == false
    end

    test "upcase" do
      {:ok, fun} = Expression.compile(~s[upcase(.status) == "OK"])
      assert Expression.evaluate(fun, %{"status" => "ok"}) == true
    end

    test "to_int" do
      {:ok, fun} = Expression.compile("to_int(.port) > 1024")
      assert Expression.evaluate(fun, %{"port" => "8080"}) == true
      assert Expression.evaluate(fun, %{"port" => "80"}) == false
    end

    test "to_string" do
      {:ok, fun} = Expression.compile(~s[to_string(.code) == "200"])
      assert Expression.evaluate(fun, %{"code" => 200}) == true
    end

    test "now returns a timestamp" do
      {:ok, fun} = Expression.compile("now() > 0")
      assert Expression.evaluate(fun, %{}) == true
    end

    test "contains as function" do
      {:ok, fun} = Expression.compile(~s[contains(.msg, "error")])
      assert Expression.evaluate(fun, %{"msg" => "an error occurred"}) == true
      assert Expression.evaluate(fun, %{"msg" => "all good"}) == false
    end

    test "starts_with as function" do
      {:ok, fun} = Expression.compile(~s[starts_with(.path, "/api")])
      assert Expression.evaluate(fun, %{"path" => "/api/v1"}) == true
    end

    test "ends_with as function" do
      {:ok, fun} = Expression.compile(~s[ends_with(.file, ".log")])
      assert Expression.evaluate(fun, %{"file" => "app.log"}) == true
    end

    test "match as function" do
      {:ok, fun} = Expression.compile(~s[match(.msg, "\\\\d+")])
      assert Expression.evaluate(fun, %{"msg" => "error 42"}) == true
      assert Expression.evaluate(fun, %{"msg" => "no digits"}) == false
    end
  end

  describe "compile and evaluate — nested fields" do
    test "nested field access" do
      {:ok, fun} = Expression.compile(~s[.request.path == "/api/health"])
      event = %{"request" => %{"path" => "/api/health"}}
      assert Expression.evaluate(fun, event) == true
    end

    test "deeply nested field" do
      {:ok, fun} = Expression.compile(".a.b.c > 0")
      event = %{"a" => %{"b" => %{"c" => 42}}}
      assert Expression.evaluate(fun, event) == true
    end

    test "missing nested field returns nil" do
      {:ok, fun} = Expression.compile("exists(.request.headers.auth)")
      event = %{"request" => %{"path" => "/api"}}
      assert Expression.evaluate(fun, event) == false
    end
  end

  describe "compile and evaluate — arithmetic" do
    test "addition" do
      {:ok, fun} = Expression.compile(".bytes_in + .bytes_out > 1000")
      assert Expression.evaluate(fun, %{"bytes_in" => 600, "bytes_out" => 500}) == true
      assert Expression.evaluate(fun, %{"bytes_in" => 100, "bytes_out" => 200}) == false
    end

    test "subtraction" do
      {:ok, fun} = Expression.compile(".end_time - .start_time > 5")
      assert Expression.evaluate(fun, %{"end_time" => 100, "start_time" => 90}) == true
    end

    test "multiplication" do
      {:ok, fun} = Expression.compile(".rate * .count > 100")
      assert Expression.evaluate(fun, %{"rate" => 5, "count" => 25}) == true
    end

    test "division" do
      {:ok, fun} = Expression.compile(".total / .count > 10")
      assert Expression.evaluate(fun, %{"total" => 100, "count" => 5}) == true
    end

    test "string concatenation with +" do
      {:ok, fun} = Expression.compile(~s[.first + " " + .last == "John Doe"])

      assert Expression.evaluate(fun, %{"first" => "John", "last" => "Doe"}) == true
    end
  end

  describe "compile and evaluate — literals as standalone" do
    test "true" do
      {:ok, fun} = Expression.compile("true")
      assert Expression.evaluate(fun, %{}) == true
    end

    test "false" do
      {:ok, fun} = Expression.compile("false")
      assert Expression.evaluate(fun, %{}) == false
    end

    test "integer" do
      {:ok, fun} = Expression.compile("42")
      assert Expression.evaluate(fun, %{}) == 42
    end

    test "string" do
      {:ok, fun} = Expression.compile(~s["hello"])
      assert Expression.evaluate(fun, %{}) == "hello"
    end

    test "null" do
      {:ok, fun} = Expression.compile("null")
      assert Expression.evaluate(fun, %{}) == nil
    end
  end

  describe "compile! and error cases" do
    test "compile! raises on invalid expression" do
      assert_raise ArgumentError, ~r/failed to compile/, fn ->
        Expression.compile!("")
      end
    end

    test "compile returns error on invalid syntax" do
      assert {:error, _} = Expression.compile("@invalid")
    end

    test "compile returns error on empty string" do
      assert {:error, "empty expression"} = Expression.compile("")
    end

    test "compile returns error on unknown function" do
      assert {:error, _} = Expression.compile("unknown_func(.x)")
    end

    test "compile returns error on unterminated string" do
      assert {:error, _} = Expression.compile(~s[.x == "hello])
    end

    test "compile returns error on missing paren" do
      assert {:error, _} = Expression.compile("(.x + .y")
    end
  end

  describe "valid?/1" do
    test "valid expression" do
      assert Expression.valid?(".severity > 3")
    end

    test "valid complex expression" do
      assert Expression.valid?(~s[.source == "cloudtrail" and .severity > 3])
    end

    test "invalid expression" do
      refute Expression.valid?("")
    end

    test "invalid syntax" do
      refute Expression.valid?("@bad")
    end
  end

  describe "edge cases" do
    test "missing field in comparison returns false" do
      {:ok, fun} = Expression.compile(".missing > 5")
      assert Expression.evaluate(fun, %{}) == false
    end

    test "nil field in equality check" do
      {:ok, fun} = Expression.compile(".x == null")
      assert Expression.evaluate(fun, %{}) == true
      assert Expression.evaluate(fun, %{"x" => nil}) == true
      assert Expression.evaluate(fun, %{"x" => 5}) == false
    end

    test "arithmetic with missing field returns nil" do
      {:ok, fun} = Expression.compile(".x + .y")
      assert Expression.evaluate(fun, %{"x" => 5}) == nil
    end

    test "division by zero returns nil" do
      {:ok, fun} = Expression.compile(".x / 0")
      assert Expression.evaluate(fun, %{"x" => 10}) == nil
    end

    test "negation" do
      {:ok, fun} = Expression.compile("-.x")
      assert Expression.evaluate(fun, %{"x" => 5}) == -5
    end

    test "double negation" do
      {:ok, fun} = Expression.compile("not not .active")
      assert Expression.evaluate(fun, %{"active" => true}) == true
      assert Expression.evaluate(fun, %{"active" => false}) == false
    end

    test "whitespace tolerance" do
      {:ok, fun} = Expression.compile("  .severity   >   3  ")
      assert Expression.evaluate(fun, %{"severity" => 5}) == true
    end

    test "bare identifier as field name" do
      {:ok, fun} = Expression.compile("severity > 3")
      assert Expression.evaluate(fun, %{"severity" => 5}) == true
    end

    test "float comparison" do
      {:ok, fun} = Expression.compile(".score > 3.14")
      assert Expression.evaluate(fun, %{"score" => 4.0}) == true
      assert Expression.evaluate(fun, %{"score" => 2.0}) == false
    end
  end
end
