defmodule Boulder.SyslogGenerator do
  @moduledoc """
  Generates highly realistic network device syslog messages conforming to RFC 5424 and RFC 3164.
  Includes structured Palo Alto firewall CSV streams, Cisco switch link state and port security alerts,
  router OSPF/BGP adjacency flaps, and Cisco IP SLA/SD-WAN latency & packet jitter records.
  """

  @months ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

  # Curated hostnames for network topology
  @firewalls ["palo-fw-01", "palo-fw-02", "perimeter-fw-03"]
  @switches ["core-sw-01", "access-sw-10", "dist-sw-02", "datacenter-sw-05"]
  @routers ["wan-router-01", "edge-router-02", "branch-rt-10", "mpls-gateway-01"]

  @doc """
  Generates a random network device syslog message.
  Options:
    - `:rfc` - `:rfc5424` or `:rfc3164` (defaults to a random choice)
    - `:hostname` - String hostname (defaults to a network device)
    - `:severity` - Integer 0..7 (defaults to logical network distributions)
    - `:facility` - Integer 0..23 (defaults to local7/local4)
  """
  def generate(opts \\ []) do
    rfc = Keyword.get(opts, :rfc) || Enum.random([:rfc5424, :rfc5424, :rfc3164]) # favor 5424 slightly
    now = DateTime.utc_now()

    # 1. Decide what kind of network event to generate based on weighted probability
    {device_type, app_name, severity, facility, message} = generate_network_event(now)

    hostname =
      Keyword.get(opts, :hostname) ||
        case device_type do
          "firewall" -> Enum.random(@firewalls)
          "switch" -> Enum.random(@switches)
          "router" -> Enum.random(@routers)
        end

    severity = Keyword.get(opts, :severity) || severity
    facility = Keyword.get(opts, :facility) || facility
    pri = (facility * 8) + severity
    proc_id = if :rand.uniform() > 0.4, do: Integer.to_string(Enum.random(100..32768)), else: nil

    case rfc do
      :rfc5424 ->
        # RFC 5424 format: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID STRUCTURED-DATA MSG
        timestamp = DateTime.to_iso8601(now)
        msg_id = if :rand.uniform() > 0.5, do: "ID#{Enum.random(1000..9999)}", else: "-"
        proc_id_str = proc_id || "-"
        "<#{pri}>1 #{timestamp} #{hostname} #{app_name} #{proc_id_str} #{msg_id} - #{message}"

      :rfc3164 ->
        # RFC 3164 format: <PRI>TIMESTAMP HOSTNAME APP-NAME[PROCID]: MSG
        timestamp = format_rfc3164_timestamp(now)
        app_part = if proc_id, do: "#{app_name}[#{proc_id}]", else: app_name
        "<#{pri}>#{timestamp} #{hostname} #{app_part}: #{message}"
    end
  end

  # --- Weighted Network Event Generator ---
  # Generates realistic network profiles:
  # - Traffic flow: Allow / Deny (70%)
  # - Jitter & Latency SLAs: Normal (12%) / High Jitter violation (5%)
  # - Switch Link Flaps: Core and edge port Up/Down transitions (5%)
  # - Routing Flaps: OSPF/BGP resets (4%)
  # - Security Threats: Intrusion and brute force blocks (2%)
  # - CPU Resource Spikes (2%)
  defp generate_network_event(now) do
    r = :rand.uniform(100)
    cond do
      # 1. Security Threat Event (2%)
      r <= 2 ->
        # Emergency (0) or Alert (1) or Critical (2)
        sev = Enum.random([1, 2])
        fac = 4 # auth
        {type, app, msg} = generate_threat_event(now)
        {type, app, sev, fac, msg}

      # 2. Hardware Resource Spike (2%)
      r <= 4 ->
        # Warning (4)
        sev = 4
        fac = 3 # daemon
        {type, app, msg} = generate_cpu_spike()
        {type, app, sev, fac, msg}

      # 3. Dynamic Routing Protocols (4%)
      r <= 8 ->
        # Notice (5) or Warning (4)
        sev = Enum.random([4, 5])
        fac = 16 # local0
        {type, app, msg} = generate_routing_flap()
        {type, app, sev, fac, msg}

      # 4. Port and Interface Link Flaps (5%)
      r <= 13 ->
        # Notice (5) or Warning (4) or Error (3)
        sev = Enum.random([3, 4, 5])
        fac = 16 # local0
        {type, app, msg} = generate_link_flap()
        {type, app, sev, fac, msg}

      # 5. Jitter SLA Violation Event (5% - Specific User Request!)
      r <= 18 ->
        # Warning (4) or Error (3)
        sev = Enum.random([3, 4])
        fac = 16 # local0
        {type, app, msg} = generate_jitter_violation()
        {type, app, sev, fac, msg}

      # 6. Normal IP SLA Telemetry (12%)
      r <= 30 ->
        # Informational (6)
        sev = 6
        fac = 16
        {type, app, msg} = generate_normal_sla()
        {type, app, sev, fac, msg}

      # 7. Standard Firewall Traffic Flow (70%)
      true ->
        # Informational (6) or Notice (5)
        sev = Enum.random([5, 6])
        fac = 20 # local4
        {type, app, msg} = generate_firewall_traffic(now)
        {type, app, sev, fac, msg}
    end
  end

  # --- Specific Event Generator Subsections ---

  defp generate_firewall_traffic(now) do
    # Generates standard Palo Alto Traffic CSV log
    src_ip = "192.168.#{Enum.random(10..200)}.#{Enum.random(2..254)}"
    dst_ip = "10.0.#{Enum.random(10..200)}.#{Enum.random(2..254)}"
    rule = Enum.random(["allow-internal-corp", "allow-web-outbound", "default-deny-perimeter"])
    proto = Enum.random(["tcp", "udp", "icmp"])
    
    # 90% allowed, 10% denied
    action = if :rand.uniform() > 0.1, do: "allow", else: "deny"
    
    in_port = Enum.random(1024..65535)
    out_port = Enum.random([80, 443, 22, 53, 3389, 445])
    
    in_interface = "ethernet1/#{Enum.random(1..4)}"
    out_interface = "ethernet1/#{Enum.random(5..8)}"

    ts_str = format_palo_alto_time(now)

    # Standard Palo Alto fields CSV message
    msg = "1,#{ts_str},007283912,TRAFFIC,end,1,#{ts_str},#{src_ip},#{dst_ip},198.51.100.1,#{dst_ip},#{rule},,web-browsing,vsys1,trust,untrust,#{in_interface},#{out_interface},default-log,#{ts_str},3456,1,#{in_port},#{out_port},0,0,0x0,#{proto},#{action},2456,1200,1256,15,#{ts_str},5,any,0,0,0,0,0,vsys1"
    
    {"firewall", "TRAFFIC", msg}
  end

  defp generate_threat_event(now) do
    # Generates Palo Alto Threat CSV log
    src_ip = Enum.random(["185.220.101.5", "203.0.113.88", "198.51.100.12", "192.168.20.14"])
    dst_ip = "10.0.50.4"
    in_port = Enum.random(1024..65535)
    
    ts_str = format_palo_alto_time(now)

    {threat_name, threat_category, port, app_name} = 
      if :rand.uniform() > 0.5 do
        {"SSH Brute Force Attempt(40012)", "vulnerability", 22, "ssh"}
      else
        {"SQL Injection Attempt(40013)", "vulnerability", 80, "web-browsing"}
      end

    msg = "1,#{ts_str},007283912,THREAT,#{threat_category},1,#{ts_str},#{src_ip},#{dst_ip},198.51.100.1,#{dst_ip},perimeter-block-rule,,db-admin,,#{app_name},vsys1,trust,untrust,ethernet1/1,ethernet1/2,default-log,#{ts_str},1001,1,#{in_port},#{port},0,0,0x0,tcp,deny,#{threat_name},34912,critical,any,0,0,0,0,0,vsys1"

    {"firewall", "THREAT", msg}
  end

  defp generate_link_flap do
    # Cisco Switch port state changes
    intf = "GigabitEthernet0/#{Enum.random(1..48)}"
    state = Enum.random(["down", "up"])
    msg = "%LINK-3-UPDOWN: Interface #{intf}, changed state to #{state}"
    {"switch", "LINK", msg}
  end

  defp generate_routing_flap do
    # OSPF or BGP Neighbor changes
    if :rand.uniform() > 0.5 do
      nbr = "10.10.100.#{Enum.random(1..254)}"
      intf = "GigabitEthernet0/#{Enum.random(1..4)}"
      state = Enum.random(["DOWN, Neighbor Down: Dead timer expired", "FULL, Loading Done"])
      msg = "%OSPF-5-ADJCHG: Process 1, Nbr #{nbr} on #{intf} from FULL to #{state}"
      {"router", "OSPF", msg}
    else
      nbr = "192.168.#{Enum.random(1..20)}.#{Enum.random(1..254)}"
      state = Enum.random(["Down - BGP Notification sent", "Up - Established"])
      msg = "%BGP-5-ADJCHANGE: neighbor #{nbr} #{state}"
      {"router", "BGP", msg}
    end
  end

  defp generate_normal_sla do
    # High-performance standard telemetry logs (low jitter < 3ms)
    latency = :rand.uniform() * 4.0 + 1.0 # 1.0ms to 5.0ms
    jitter = :rand.uniform() * 1.5 + 0.2  # 0.2ms to 1.7ms
    loss = if :rand.uniform() > 0.98, do: 0.1, else: 0.0

    probe_id = Enum.random([101, 201, 301])
    msg = "%RTT-6-IPSLADATA: IP SLA (#{probe_id}) Probe Successful: Latency #{Float.round(latency, 2)}ms, Jitter #{Float.round(jitter, 2)}ms, Loss #{Float.round(loss, 2)}%"
    {"router", "IP_SLA", msg}
  end

  defp generate_jitter_violation do
    # Dynamic SD-WAN SLA Violation representing WAN Jitter Spike!
    probe_id = Enum.random([101, 201, 301])
    latency = :rand.uniform() * 30.0 + 35.0  # 35ms to 65ms (high latency)
    jitter = :rand.uniform() * 15.0 + 12.0   # 12ms to 27ms (severe jitter anomaly!)
    loss = :rand.uniform() * 1.5             # 0% to 1.5% loss

    if :rand.uniform() > 0.5 do
      msg = "%RTT-3-IPSLATHRESHOLD: IP SLA (#{probe_id}) Jitter Threshold Exceeded: Latency #{Float.round(latency, 2)}ms, Jitter #{Float.round(jitter, 2)}ms, Loss #{Float.round(loss, 2)}%"
      {"router", "IP_SLA_ALERT", msg}
    else
      tunnel = "10.0.#{Enum.random(1..10)}.1"
      msg = "%SDWAN-3-SLA_VIOLATION: Interface ge0/2, tunnel #{tunnel}: SLA Violation - Jitter is #{Float.round(jitter, 2)}ms (Threshold 10ms), packet loss #{Float.round(loss, 2)}%"
      {"router", "SDWAN_ALERT", msg}
    end
  end

  defp generate_cpu_spike do
    # Device high CPU spike
    pct = Enum.random(91..98)
    msg = "%SYS-5-CPU_RISING_THRESHOLD: Threshold exceeded - CPU Utilization is #{pct}%"
    {"router", "SYSTEM", msg}
  end

  # --- Date/Time formatting helpers ---

  defp format_palo_alto_time(dt) do
    # Format: YYYY/MM/DD HH:MM:SS
    year = dt.year
    month = String.pad_leading(Integer.to_string(dt.month), 2, "0")
    day = String.pad_leading(Integer.to_string(dt.day), 2, "0")
    hour = String.pad_leading(Integer.to_string(dt.hour), 2, "0")
    minute = String.pad_leading(Integer.to_string(dt.minute), 2, "0")
    second = String.pad_leading(Integer.to_string(dt.second), 2, "0")
    
    "#{year}/#{month}/#{day} #{hour}:#{minute}:#{second}"
  end

  defp format_rfc3164_timestamp(dt) do
    month = Enum.at(@months, dt.month - 1)
    day_str = if dt.day < 10, do: " #{dt.day}", else: Integer.to_string(dt.day)
    hour = String.pad_leading(Integer.to_string(dt.hour), 2, "0")
    minute = String.pad_leading(Integer.to_string(dt.minute), 2, "0")
    second = String.pad_leading(Integer.to_string(dt.second), 2, "0")

    "#{month} #{day_str} #{hour}:#{minute}:#{second}"
  end
end
