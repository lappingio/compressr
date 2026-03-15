defmodule Compressr.Auth.ApiToken do
  @moduledoc """
  API token management backed by DynamoDB.

  Tokens are stored as SHA-256 hashes in the config table with:
    pk = "api_token"
    sk = "\#{token_hash}"

  Raw tokens have the format: cpr_<32 random bytes base64url encoded>
  """

  @token_prefix "cpr_"

  @doc """
  Create a new API token for a user.

  Returns `{:ok, raw_token}` where raw_token is the only time the
  plaintext token is available.
  """
  @spec create(Compressr.Auth.User.t()) :: {:ok, String.t()}
  def create(%Compressr.Auth.User{} = user) do
    raw_token = generate_token()
    token_hash = hash_token(raw_token)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    item = %{
      "pk" => "api_token",
      "sk" => token_hash,
      "user_sub" => user.sub,
      "user_provider" => user.provider,
      "user_email" => user.email || "",
      "created_at" => now
    }

    ExAws.Dynamo.put_item(table_name(), item)
    |> ExAws.request!()

    {:ok, raw_token}
  end

  @doc """
  Verify a raw token and return the associated user if valid.
  """
  @spec verify(String.t()) :: {:ok, Compressr.Auth.User.t()} | {:error, :invalid_token}
  def verify(raw_token) do
    token_hash = hash_token(raw_token)

    result =
      ExAws.Dynamo.get_item(table_name(), %{"pk" => "api_token", "sk" => token_hash})
      |> ExAws.request!()

    case result do
      %{"Item" => item} when map_size(item) > 0 ->
        provider = get_s(item, "user_provider")
        sub = get_s(item, "user_sub")
        Compressr.Auth.User.get_by_provider_and_sub(provider, sub)
        |> case do
          {:ok, nil} -> {:error, :invalid_token}
          {:ok, user} -> {:ok, user}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  @doc """
  Revoke (delete) a token.
  """
  @spec revoke(String.t()) :: :ok
  def revoke(raw_token) do
    token_hash = hash_token(raw_token)

    ExAws.Dynamo.delete_item(table_name(), %{"pk" => "api_token", "sk" => token_hash})
    |> ExAws.request!()

    :ok
  end

  @doc """
  List tokens for a user (metadata only, no hashes).
  """
  @spec list_for_user(Compressr.Auth.User.t()) :: {:ok, [map()]}
  def list_for_user(%Compressr.Auth.User{} = user) do
    result =
      ExAws.Dynamo.scan(table_name(),
        filter_expression: "pk = :pk AND user_sub = :sub AND user_provider = :provider",
        expression_attribute_values: [
          pk: "api_token",
          sub: user.sub,
          provider: user.provider
        ]
      )
      |> ExAws.request!()

    tokens =
      result
      |> Map.get("Items", [])
      |> Enum.map(fn item ->
        %{
          user_email: get_s(item, "user_email"),
          user_sub: get_s(item, "user_sub"),
          user_provider: get_s(item, "user_provider"),
          created_at: get_s(item, "created_at")
        }
      end)

    {:ok, tokens}
  end

  defp generate_token do
    random_bytes = :crypto.strong_rand_bytes(32)
    @token_prefix <> Base.url_encode64(random_bytes, padding: false)
  end

  defp hash_token(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
  end

  defp table_name do
    prefix = Application.get_env(:compressr, :dynamodb_table_prefix, "compressr_")
    "#{prefix}config"
  end

  defp get_s(item, key) do
    case Map.get(item, key) do
      %{"S" => val} -> val
      _ -> nil
    end
  end
end
