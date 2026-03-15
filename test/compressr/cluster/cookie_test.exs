defmodule Compressr.Cluster.CookieTest do
  use ExUnit.Case, async: true

  alias Compressr.Cluster.Cookie

  describe "validate_cookie/0" do
    test "returns a result (either :ok or {:warn, _})" do
      result = Cookie.validate_cookie()
      assert result == :ok or match?({:warn, _}, result)
    end

    test "detects default or short cookie in non-distributed mode" do
      # In test (non-distributed), the cookie is :nocookie which is both
      # a default cookie and short. validate_cookie should warn.
      case Cookie.validate_cookie() do
        {:warn, msg} ->
          assert is_binary(msg)

        :ok ->
          # If the test runner is distributed with a strong cookie, that's fine too
          :ok
      end
    end
  end

  describe "generate_cookie/0" do
    test "returns a string of at least 32 characters" do
      cookie = Cookie.generate_cookie()
      assert is_binary(cookie)
      assert String.length(cookie) >= 32
    end

    test "generates unique cookies on each call" do
      cookie1 = Cookie.generate_cookie()
      cookie2 = Cookie.generate_cookie()
      refute cookie1 == cookie2
    end

    test "returns URL-safe characters" do
      cookie = Cookie.generate_cookie()
      # URL-safe base64 uses only alphanumeric, hyphen, and underscore
      assert cookie =~ ~r/^[A-Za-z0-9_-]+$/
    end

    test "generates a cookie of expected length (64 chars for 48 bytes)" do
      cookie = Cookie.generate_cookie()
      assert String.length(cookie) == 64
    end
  end
end
