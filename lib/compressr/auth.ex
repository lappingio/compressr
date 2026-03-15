defmodule Compressr.Auth do
  @moduledoc """
  Authentication context module.

  Delegates to `Compressr.Auth.User` and `Compressr.Auth.ApiToken`.
  """

  alias Compressr.Auth.{User, ApiToken}

  # User management
  defdelegate find_or_create_user(attrs), to: User, as: :find_or_create
  defdelegate get_user_by_provider_and_sub(provider, sub), to: User, as: :get_by_provider_and_sub
  defdelegate list_users(), to: User

  # API token management
  defdelegate create_api_token(user), to: ApiToken, as: :create
  defdelegate verify_api_token(raw_token), to: ApiToken, as: :verify
  defdelegate revoke_api_token(raw_token), to: ApiToken, as: :revoke
  defdelegate list_api_tokens_for_user(user), to: ApiToken, as: :list_for_user
end
