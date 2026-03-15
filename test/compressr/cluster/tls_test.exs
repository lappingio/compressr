defmodule Compressr.Cluster.TLSTest do
  use ExUnit.Case, async: true

  alias Compressr.Cluster.TLS

  describe "generate_config/1" do
    test "returns error when certfile is missing" do
      assert {:error, "certfile is required"} =
               TLS.generate_config(keyfile: "/path/to/key.pem")
    end

    test "returns error when keyfile is missing" do
      assert {:error, "keyfile is required"} =
               TLS.generate_config(certfile: "/path/to/cert.pem")
    end

    test "returns error when certfile is empty string" do
      assert {:error, "certfile is required"} =
               TLS.generate_config(certfile: "", keyfile: "/path/to/key.pem")
    end

    test "generates config with certfile and keyfile" do
      assert {:ok, %{sys_config: sys_config, vm_args: vm_args}} =
               TLS.generate_config(
                 certfile: "/path/to/cert.pem",
                 keyfile: "/path/to/key.pem"
               )

      assert is_list(sys_config)
      assert [{:ssl, [{:ssl_dist_opt, ssl_opts}]}] = sys_config
      assert Keyword.has_key?(ssl_opts, :server)
      assert Keyword.has_key?(ssl_opts, :client)

      server_opts = Keyword.get(ssl_opts, :server)
      assert {:certfile, ~c"/path/to/cert.pem"} in server_opts
      assert {:keyfile, ~c"/path/to/key.pem"} in server_opts

      assert is_list(vm_args)
      assert "-proto_dist inet_tls" in vm_args
    end

    test "includes CA cert and verify_peer when cacertfile is provided" do
      assert {:ok, %{sys_config: [{:ssl, [{:ssl_dist_opt, ssl_opts}]}]}} =
               TLS.generate_config(
                 certfile: "/path/to/cert.pem",
                 keyfile: "/path/to/key.pem",
                 cacertfile: "/path/to/ca.pem"
               )

      server_opts = Keyword.get(ssl_opts, :server)
      assert {:cacertfile, ~c"/path/to/ca.pem"} in server_opts
      assert {:verify, :verify_peer} in server_opts

      client_opts = Keyword.get(ssl_opts, :client)
      assert {:cacertfile, ~c"/path/to/ca.pem"} in client_opts
      assert {:verify, :verify_peer} in client_opts
    end

    test "allows disabling verify_peer even with cacertfile" do
      assert {:ok, %{sys_config: [{:ssl, [{:ssl_dist_opt, ssl_opts}]}]}} =
               TLS.generate_config(
                 certfile: "/path/to/cert.pem",
                 keyfile: "/path/to/key.pem",
                 cacertfile: "/path/to/ca.pem",
                 verify_peer: false
               )

      server_opts = Keyword.get(ssl_opts, :server)
      assert {:verify, :verify_none} in server_opts
    end

    test "does not include verify options when no cacertfile" do
      assert {:ok, %{sys_config: [{:ssl, [{:ssl_dist_opt, ssl_opts}]}]}} =
               TLS.generate_config(
                 certfile: "/path/to/cert.pem",
                 keyfile: "/path/to/key.pem"
               )

      server_opts = Keyword.get(ssl_opts, :server)
      refute Enum.any?(server_opts, fn {k, _} -> k == :cacertfile end)
      refute Enum.any?(server_opts, fn {k, _} -> k == :verify end)
    end
  end

  describe "verify_enabled?/0" do
    test "returns false when distribution TLS is not active" do
      # In a test environment, distribution TLS is not configured
      refute TLS.verify_enabled?()
    end
  end

  describe "status/0" do
    test "returns a map with tls_enabled, node, and alive keys" do
      status = TLS.status()
      assert is_map(status)
      assert Map.has_key?(status, :tls_enabled)
      assert Map.has_key?(status, :node)
      assert Map.has_key?(status, :alive)
      assert is_boolean(status.tls_enabled)
    end
  end
end
