defmodule Compressr.Cluster.TLS do
  @moduledoc """
  Generates and manages TLS configuration for Erlang distribution.

  Erlang distribution uses plain TCP by default, which means any node that can
  reach EPMD and the distribution port can join the cluster and execute arbitrary
  code. This module provides helpers to enable `inet_tls_dist`, which encrypts
  all inter-node traffic.

  ## Quick start

  1. Generate certificates (e.g. with `openssl` or `mix phx.gen.cert`).
  2. Set environment variables:
     - `DISTRIBUTION_TLS_CERTFILE` — path to the PEM certificate
     - `DISTRIBUTION_TLS_KEYFILE`  — path to the PEM private key
     - `DISTRIBUTION_TLS_CACERTFILE` — path to the CA certificate (optional, enables peer verification)
  3. Include the generated `vm.args` flags when starting the release.

  See `rel/env.sh.eex` and `rel/vm.args.eex` for release integration.
  """

  @type tls_opts :: %{
          certfile: String.t(),
          keyfile: String.t(),
          cacertfile: String.t() | nil
        }

  @doc """
  Generates configuration artifacts for enabling TLS on Erlang distribution.

  Returns a map with:
  - `:sys_config` — an Erlang `sys.config`-compatible term for `inet_tls_dist`
  - `:vm_args` — a list of `vm.args` flag strings

  ## Options

  - `:certfile` (required) — path to the TLS certificate PEM file
  - `:keyfile` (required) — path to the TLS private key PEM file
  - `:cacertfile` (optional) — path to the CA certificate for peer verification
  - `:verify_peer` (optional, default `true` when `:cacertfile` is provided) —
    whether to verify the peer certificate
  """
  @spec generate_config(keyword()) ::
          {:ok, %{sys_config: term(), vm_args: [String.t()]}} | {:error, String.t()}
  def generate_config(opts) do
    certfile = Keyword.get(opts, :certfile)
    keyfile = Keyword.get(opts, :keyfile)
    cacertfile = Keyword.get(opts, :cacertfile)

    with :ok <- validate_required(certfile, "certfile"),
         :ok <- validate_required(keyfile, "keyfile") do
      verify_peer = Keyword.get(opts, :verify_peer, cacertfile != nil)

      ssl_dist_opts = build_ssl_dist_opts(certfile, keyfile, cacertfile, verify_peer)
      sys_config = [{:ssl, [{:ssl_dist_opt, ssl_dist_opts}]}]

      vm_args = [
        "-proto_dist inet_tls",
        "-ssl_dist_optfile config/ssl_dist.conf"
      ]

      {:ok, %{sys_config: sys_config, vm_args: vm_args}}
    end
  end

  @doc """
  Checks whether TLS is currently active on Erlang distribution.

  Returns `true` if the distribution protocol module is `inet_tls_dist`,
  `false` otherwise (including when the node is not alive).
  """
  @spec verify_enabled?() :: boolean()
  def verify_enabled? do
    case :init.get_argument(:proto_dist) do
      {:ok, [[~c"inet_tls"]]} -> true
      {:ok, args} -> Enum.any?(args, fn a -> a == ~c"inet_tls" end)
      :error -> false
    end
  end

  @doc """
  Returns a map of TLS distribution status information suitable for diagnostics.
  """
  @spec status() :: map()
  def status do
    %{
      tls_enabled: verify_enabled?(),
      node: node(),
      alive: Node.alive?()
    }
  end

  # Private helpers

  defp validate_required(nil, name), do: {:error, "#{name} is required"}
  defp validate_required("", name), do: {:error, "#{name} is required"}
  defp validate_required(_val, _name), do: :ok

  defp build_ssl_dist_opts(certfile, keyfile, cacertfile, verify_peer) do
    base = [
      server: [
        {:certfile, to_charlist(certfile)},
        {:keyfile, to_charlist(keyfile)},
        {:secure_renegotiate, true}
      ],
      client: [
        {:certfile, to_charlist(certfile)},
        {:keyfile, to_charlist(keyfile)},
        {:secure_renegotiate, true}
      ]
    ]

    if cacertfile do
      verify_opts =
        if verify_peer do
          [{:verify, :verify_peer}, {:cacertfile, to_charlist(cacertfile)}]
        else
          [{:verify, :verify_none}, {:cacertfile, to_charlist(cacertfile)}]
        end

      Keyword.update!(base, :server, &(&1 ++ verify_opts))
      |> Keyword.update!(:client, &(&1 ++ verify_opts))
    else
      base
    end
  end
end
