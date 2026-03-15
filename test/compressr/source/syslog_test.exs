defmodule Compressr.Source.SyslogTest do
  use ExUnit.Case, async: true

  alias Compressr.Source.Syslog

  describe "validate_config/1" do
    test "valid UDP config" do
      assert :ok = Syslog.validate_config(%{"udp_port" => 514, "protocol" => "udp"})
    end

    test "valid TCP config" do
      assert :ok = Syslog.validate_config(%{"tcp_port" => 514, "protocol" => "tcp"})
    end

    test "valid both config" do
      config = %{"udp_port" => 514, "tcp_port" => 1514, "protocol" => "both"}
      assert :ok = Syslog.validate_config(config)
    end

    test "defaults to udp protocol" do
      assert :ok = Syslog.validate_config(%{"udp_port" => 514})
    end

    test "rejects missing udp_port for udp protocol" do
      assert {:error, {:missing_fields, ["udp_port"]}} =
               Syslog.validate_config(%{"protocol" => "udp"})
    end

    test "rejects missing tcp_port for tcp protocol" do
      assert {:error, {:missing_fields, ["tcp_port"]}} =
               Syslog.validate_config(%{"protocol" => "tcp"})
    end

    test "rejects invalid protocol" do
      assert {:error, {:invalid_protocol, "websocket"}} =
               Syslog.validate_config(%{"protocol" => "websocket"})
    end
  end

  describe "parse_rfc5424/1" do
    test "parses a standard RFC 5424 message" do
      msg = "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 - An application event log entry"

      assert {:ok, event} = Syslog.parse_rfc5424(msg)
      assert event["_raw"] == msg
      assert event["facility"] == 20
      assert event["facility_name"] == "local4"
      assert event["severity"] == 5
      assert event["severity_name"] == "notice"
      assert event["syslog_version"] == 1
      assert event["timestamp"] == "2003-10-11T22:14:15.003Z"
      assert event["hostname"] == "mymachine.example.com"
      assert event["app_name"] == "evntslog"
      assert event["procid"] == nil
      assert event["msgid"] == "ID47"
      assert event["message"] == "An application event log entry"
      assert event["format"] == "rfc5424"
    end

    test "parses RFC 5424 with nil values" do
      msg = "<34>1 2023-06-15T10:30:00Z - - - - - No host or app"

      assert {:ok, event} = Syslog.parse_rfc5424(msg)
      assert event["hostname"] == nil
      assert event["app_name"] == nil
      assert event["procid"] == nil
      assert event["msgid"] == nil
      assert event["message"] == "No host or app"
    end

    test "parses RFC 5424 with structured data" do
      msg = "<165>1 2003-10-11T22:14:15.003Z host app - - [exampleSDID@32473 iut=\"3\" eventSource=\"Application\"] A message"

      assert {:ok, event} = Syslog.parse_rfc5424(msg)
      assert event["message"] == "A message"
      assert event["hostname"] == "host"
    end

    test "parses kern.emerg priority" do
      msg = "<0>1 2023-01-01T00:00:00Z host app - - - Kernel emergency"

      assert {:ok, event} = Syslog.parse_rfc5424(msg)
      assert event["facility"] == 0
      assert event["facility_name"] == "kern"
      assert event["severity"] == 0
      assert event["severity_name"] == "emerg"
    end

    test "parses auth.info priority" do
      # auth=4, info=6 => 4*8+6 = 38
      msg = "<38>1 2023-01-01T00:00:00Z host sshd - - - Login attempt"

      assert {:ok, event} = Syslog.parse_rfc5424(msg)
      assert event["facility"] == 4
      assert event["facility_name"] == "auth"
      assert event["severity"] == 6
      assert event["severity_name"] == "info"
    end

    test "returns :error for non-RFC 5424 message" do
      assert :error = Syslog.parse_rfc5424("just a plain string")
    end

    test "returns :error for RFC 3164 message" do
      msg = "<34>Oct 11 22:14:15 mymachine su: 'su root' failed"
      assert :error = Syslog.parse_rfc5424(msg)
    end
  end

  describe "parse_rfc3164/1" do
    test "parses a standard RFC 3164 message" do
      msg = "<34>Oct 11 22:14:15 mymachine su: 'su root' failed for lonvick on /dev/pts/8"

      assert {:ok, event} = Syslog.parse_rfc3164(msg)
      assert event["_raw"] == msg
      assert event["facility"] == 4
      assert event["facility_name"] == "auth"
      assert event["severity"] == 2
      assert event["severity_name"] == "crit"
      assert event["timestamp"] == "Oct 11 22:14:15"
      assert event["hostname"] == "mymachine"
      assert event["app_name"] == "su"
      assert event["message"] == "'su root' failed for lonvick on /dev/pts/8"
      assert event["format"] == "rfc3164"
    end

    test "parses RFC 3164 with PID" do
      msg = "<13>Jan  5 10:30:00 myhost sshd[12345]: Accepted publickey for user"

      assert {:ok, event} = Syslog.parse_rfc3164(msg)
      assert event["app_name"] == "sshd"
      assert event["message"] == "Accepted publickey for user"
    end

    test "parses RFC 3164 with single-digit day" do
      msg = "<86>Dec  1 08:00:00 router cron: Job started"

      assert {:ok, event} = Syslog.parse_rfc3164(msg)
      assert event["timestamp"] == "Dec  1 08:00:00"
      assert event["hostname"] == "router"
    end

    test "parses user.info priority" do
      # user=1, info=6 => 1*8+6 = 14
      msg = "<14>Mar 15 12:00:00 appserver myapp: Request processed"

      assert {:ok, event} = Syslog.parse_rfc3164(msg)
      assert event["facility"] == 1
      assert event["facility_name"] == "user"
      assert event["severity"] == 6
      assert event["severity_name"] == "info"
    end

    test "returns :error for non-syslog message" do
      assert :error = Syslog.parse_rfc3164("just a plain string")
    end

    test "returns :error for RFC 5424 message" do
      msg = "<165>1 2003-10-11T22:14:15.003Z host app - - - A message"
      assert :error = Syslog.parse_rfc3164(msg)
    end
  end

  describe "parse_message/1" do
    test "parses RFC 5424 message" do
      msg = "<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 - An event"

      event = Syslog.parse_message(msg)
      assert event["format"] == "rfc5424"
    end

    test "parses RFC 3164 message" do
      msg = "<34>Oct 11 22:14:15 mymachine su: 'su root' failed"

      event = Syslog.parse_message(msg)
      assert event["format"] == "rfc3164"
    end

    test "falls back to raw event for unparseable messages" do
      msg = "This is not a syslog message at all"

      event = Syslog.parse_message(msg)
      assert event["_raw"] == msg
      assert event["_time"] != nil
      refute Map.has_key?(event, "format")
    end

    test "handles empty string" do
      event = Syslog.parse_message("")
      assert event["_raw"] == ""
    end
  end

  describe "handle_data/2" do
    test "parses multiple newline-delimited messages" do
      data = """
      <165>1 2003-10-11T22:14:15.003Z host app - - - Message 1
      <34>Oct 11 22:14:15 mymachine su: Message 2
      """

      {:ok, state} = Syslog.init(%{})
      {:ok, events, _state} = Syslog.handle_data(data, state)

      assert length(events) == 2
      assert Enum.at(events, 0)["format"] == "rfc5424"
      assert Enum.at(events, 1)["format"] == "rfc3164"
    end

    test "handles single message without newline" do
      data = "<34>Oct 11 22:14:15 mymachine su: Single message"

      {:ok, state} = Syslog.init(%{})
      {:ok, events, _state} = Syslog.handle_data(data, state)

      assert length(events) == 1
    end
  end

  describe "init/1 and stop/1" do
    test "init returns ok with state" do
      assert {:ok, state} = Syslog.init(%{"udp_port" => 514})
      assert state.config == %{"udp_port" => 514}
    end

    test "stop returns ok" do
      {:ok, state} = Syslog.init(%{})
      assert :ok = Syslog.stop(state)
    end
  end

  describe "UDP message reception" do
    test "receives and parses UDP syslog message" do
      # Start a UDP socket to receive messages
      {:ok, recv_socket} = :gen_udp.open(0, [:binary, active: false])
      {:ok, port} = :inet.port(recv_socket)

      # Initialize the syslog source
      {:ok, state} = Syslog.init(%{"udp_port" => port, "protocol" => "udp"})

      # Send a syslog message via UDP
      {:ok, send_socket} = :gen_udp.open(0, [:binary])
      msg = "<34>Oct 11 22:14:15 mymachine su: UDP test message"
      :ok = :gen_udp.send(send_socket, ~c"127.0.0.1", port, msg)

      # Receive the raw data
      {:ok, {_addr, _port, data}} = :gen_udp.recv(recv_socket, 0, 1000)

      # Process through the source
      {:ok, events, _new_state} = Syslog.handle_data(data, state)

      assert length(events) == 1
      event = hd(events)
      assert event["format"] == "rfc3164"
      assert event["message"] == "UDP test message"

      :gen_udp.close(recv_socket)
      :gen_udp.close(send_socket)
    end
  end
end
