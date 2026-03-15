defmodule Compressr.Source.Syslog do
  @moduledoc """
  Syslog source implementation.

  Listens for syslog messages over UDP and/or TCP on configurable ports.
  Parses both RFC 5424 and RFC 3164 syslog message formats.

  Configuration:
    - `udp_port` - UDP port to listen on (integer, optional)
    - `tcp_port` - TCP port to listen on (integer, optional)
    - `protocol` - `:udp`, `:tcp`, or `:both` (default: `:udp`)
  """

  @behaviour Compressr.Source

  # Syslog facility names (RFC 5424 / RFC 3164)
  @facility_names %{
    0 => "kern",
    1 => "user",
    2 => "mail",
    3 => "daemon",
    4 => "auth",
    5 => "syslog",
    6 => "lpr",
    7 => "news",
    8 => "uucp",
    9 => "cron",
    10 => "authpriv",
    11 => "ftp",
    16 => "local0",
    17 => "local1",
    18 => "local2",
    19 => "local3",
    20 => "local4",
    21 => "local5",
    22 => "local6",
    23 => "local7"
  }

  @severity_names %{
    0 => "emerg",
    1 => "alert",
    2 => "crit",
    3 => "err",
    4 => "warning",
    5 => "notice",
    6 => "info",
    7 => "debug"
  }

  @impl true
  def validate_config(config) do
    protocol = Map.get(config, "protocol", "udp")

    cond do
      protocol in ["udp", "both"] and not is_integer(Map.get(config, "udp_port")) ->
        {:error, {:missing_fields, ["udp_port"]}}

      protocol in ["tcp", "both"] and not is_integer(Map.get(config, "tcp_port")) ->
        {:error, {:missing_fields, ["tcp_port"]}}

      protocol not in ["udp", "tcp", "both"] ->
        {:error, {:invalid_protocol, protocol}}

      true ->
        :ok
    end
  end

  @impl true
  def init(config) do
    {:ok, %{config: config}}
  end

  @impl true
  def handle_data(data, state) when is_binary(data) do
    events =
      data
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_message/1)

    {:ok, events, state}
  end

  @impl true
  def stop(_state) do
    :ok
  end

  @doc """
  Parse a syslog message string into a Compressr.Event map.

  Supports both RFC 5424 and RFC 3164 formats.
  """
  @spec parse_message(String.t()) :: map()
  def parse_message(message) when is_binary(message) do
    case parse_rfc5424(message) do
      {:ok, event} ->
        event

      :error ->
        case parse_rfc3164(message) do
          {:ok, event} -> event
          :error -> Compressr.Event.from_raw(message)
        end
    end
  end

  @doc """
  Parse an RFC 5424 syslog message.

  Format: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID STRUCTURED-DATA MSG
  Example: <165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 - An application event log entry
  """
  @spec parse_rfc5424(String.t()) :: {:ok, map()} | :error
  def parse_rfc5424(message) do
    # Match: <PRI>VERSION SP TIMESTAMP SP HOSTNAME SP APP-NAME SP PROCID SP MSGID SP SD SP? MSG
    regex =
      ~r/^<(\d{1,3})>(\d+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(-|(?:\[.*?\])+)\s*(.*)/s

    case Regex.run(regex, message) do
      [_full, pri_s, version_s, timestamp, hostname, app_name, procid, msgid, _sd, msg] ->
        pri = String.to_integer(pri_s)
        version = String.to_integer(version_s)

        if version >= 1 do
          {facility, severity} = decode_priority(pri)

          event =
            Compressr.Event.new(message, %{
              "facility" => facility,
              "facility_name" => Map.get(@facility_names, facility, "unknown"),
              "severity" => severity,
              "severity_name" => Map.get(@severity_names, severity, "unknown"),
              "syslog_version" => version,
              "timestamp" => timestamp,
              "hostname" => nilvalue(hostname),
              "app_name" => nilvalue(app_name),
              "procid" => nilvalue(procid),
              "msgid" => nilvalue(msgid),
              "message" => msg,
              "format" => "rfc5424"
            })

          {:ok, event}
        else
          :error
        end

      _ ->
        :error
    end
  end

  @doc """
  Parse an RFC 3164 (BSD) syslog message.

  Format: <PRI>TIMESTAMP HOSTNAME APP-NAME[PID]: MSG
  Example: <34>Oct 11 22:14:15 mymachine su: 'su root' failed
  """
  @spec parse_rfc3164(String.t()) :: {:ok, map()} | :error
  def parse_rfc3164(message) do
    # Match: <PRI>TIMESTAMP HOSTNAME MSG
    regex = ~r/^<(\d{1,3})>(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(.*)/s

    case Regex.run(regex, message) do
      [_full, pri_s, timestamp, hostname, rest] ->
        pri = String.to_integer(pri_s)
        {facility, severity} = decode_priority(pri)

        {app_name, msg} = parse_rfc3164_tag(rest)

        event =
          Compressr.Event.new(message, %{
            "facility" => facility,
            "facility_name" => Map.get(@facility_names, facility, "unknown"),
            "severity" => severity,
            "severity_name" => Map.get(@severity_names, severity, "unknown"),
            "timestamp" => timestamp,
            "hostname" => hostname,
            "app_name" => app_name,
            "message" => msg,
            "format" => "rfc3164"
          })

        {:ok, event}

      _ ->
        :error
    end
  end

  # --- Private ---

  defp decode_priority(pri) when is_integer(pri) do
    facility = div(pri, 8)
    severity = rem(pri, 8)
    {facility, severity}
  end

  defp nilvalue("-"), do: nil
  defp nilvalue(val), do: val

  defp parse_rfc3164_tag(rest) do
    case Regex.run(~r/^(\S+?)(?:\[(\d+)\])?:\s*(.*)$/s, rest) do
      [_full, app_name, _pid, msg] ->
        {app_name, msg}

      _ ->
        {nil, rest}
    end
  end
end
