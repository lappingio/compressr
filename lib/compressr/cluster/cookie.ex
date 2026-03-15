defmodule Compressr.Cluster.Cookie do
  @moduledoc """
  Erlang distribution cookie management.

  The Erlang cookie is a shared secret used to authenticate nodes joining
  a distributed cluster. A weak or default cookie is effectively no
  authentication at all — any attacker who can reach the distribution port
  can execute arbitrary code on every node.

  This module provides helpers to validate and generate secure cookies.
  """

  @min_cookie_length 32
  @default_cookies [:nocookie, :cookie, :monster]

  @doc """
  Validates the current Erlang cookie.

  Returns `:ok` if the cookie is acceptable, or `{:warn, reason}` if it is
  the default cookie or too short (fewer than #{@min_cookie_length} characters).
  """
  @spec validate_cookie() :: :ok | {:warn, String.t()}
  def validate_cookie do
    cookie = Node.get_cookie()
    cookie_str = Atom.to_string(cookie)

    cond do
      cookie in @default_cookies ->
        {:warn,
         "Erlang cookie is set to the default value '#{cookie}'. " <>
           "Set a strong random cookie via RELEASE_COOKIE or --cookie."}

      String.length(cookie_str) < @min_cookie_length ->
        {:warn,
         "Erlang cookie is only #{String.length(cookie_str)} characters long. " <>
           "Use at least #{@min_cookie_length} characters. Generate one with " <>
           "Compressr.Cluster.Cookie.generate_cookie/0."}

      true ->
        :ok
    end
  end

  @doc """
  Generates a cryptographically secure random cookie string.

  Returns a 64-character URL-safe Base64 string (48 random bytes).
  """
  @spec generate_cookie() :: String.t()
  def generate_cookie do
    :crypto.strong_rand_bytes(48)
    |> Base.url_encode64(padding: false)
  end
end
