# Boulder 🪨

An industrial-grade, ultra-high-performance Syslog benchmark client written in Elixir. `boulder` is designed to simulate thousands of concurrent network devices (firewalls, routers, and switches) sending high-throughput telemetry streams over UDP to evaluate the stress thresholds of ingestion pipelines, anomaly detectors, and SIEM servers.

---

## 🏗️ Architecture & High-Performance Design

`boulder` utilizes several advanced OTP and Erlang capabilities to sustain massive throughput with near-zero CPU overhead:

1. **Dynamic Process-per-Device Topology**: Every simulated device runs as an independent `DeviceWorker` GenServer under a `DynamicSupervisor`.
2. **Dedicated Client Sockets**: Each worker opens its own dedicated outbound UDP socket on a random local port. When sending packets to a sharded server listening with `SO_REUSEPORT`, this ensures every device's stream has a unique 4-tuple, allowing the receiving OS kernel to perfectly load-balance packets across CPU cores.
3. **Lock-Free Atomic CPU Counters**: Outbound success and error metrics are aggregated globally via Erlang's hardware-level `:atomics` module. Simulated devices perform zero-overhead increments directly on CPU registers, completely bypassing GenServer mailbox queues and scheduling bottlenecks.

---

## 📡 Realistic Network Log Generation

`boulder` produces highly realistic network syslog payloads, including:
* **Palo Alto / Panorama Firewalls**: Structured Traffic (allow/deny rules, source/destination IPs, ports, protocols) and Threat CSV entries.
* **Cisco Switches**: Physical link state notifications (`%LINK-3-UPDOWN` interfaces) and port-security alerts.
* **Cisco & Juniper Routers**: OSPF and BGP neighbor adjacency state flags (`%OSPF-5-ADJCHG`) and hardware CPU utilization alerts.
* **IP SLA & SD-WAN Tunnels**: Live latency, packet-loss, and packet-jitter telemetry, including periodic SLA jitter violations (where link jitter spikes to 15–30ms to trigger anomaly alerts).

---

## 🚀 Getting Started & Execution Instructions

### 1. Prereqs & Build
Ensure you have Elixir 1.15+ installed. In your terminal, navigate to the project directory and build the application:
```bash
mix compile
```

### 2. Launch the Application Node
To allow remote monitoring and node-to-node communication (such as the SYSiphus profiler), start `boulder` in an interactive Elixir shell (`IEx`) with a short node name:
```bash
iex --sname boulder -S mix
```

### 3. Running Benchmarks

Inside the running `iex>` shell, execute the following commands:

#### Start a Stress-Test Benchmark
To simulate `100` network devices, each sending `200` syslog messages per second (generating a total sustained load of **20,000 logs/second**), execute:
```elixir
Boulder.start_benchmark(devices: 100, rate: 200)
```

You can customize the target server IP and UDP port as options:
```elixir
Boulder.start_benchmark(
  devices: 500,
  rate: 50,
  target_host: "192.168.1.100",
  target_port: 5514
)
```

The shell will print a dynamic real-time telemetry banner indicating run elapsed-time, active devices, instantaneous logs-per-second, average speed, and cumulative counts.

#### Check Telemetry Status
Retrieve current execution metrics programmatically:
```elixir
Boulder.status()
```

#### Stop the Benchmark
Gracefully terminate all simulated device processes and close outbound UDP ports:
```elixir
Boulder.stop_benchmark()
```
