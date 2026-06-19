defmodule Boulder.Controller do
  @moduledoc """
  Coordinates syslog generation benchmarks. Opens the shared UDP socket,
  spawns and terminates thousands of simulated devices, aggregates telemetry
  using lock-free `:atomics` CPU counters, and outputs real-time sending statistics.
  """
  use GenServer

  alias Boulder.DeviceWorker

  # --- Client API ---

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a syslog generation benchmark.
  """
  def start_benchmark(opts \\ []) do
    devices = Keyword.get(opts, :devices, 100)
    rate = Keyword.get(opts, :rate, 10)
    target_host = Keyword.get(opts, :target_host, "127.0.0.1")
    target_port = Keyword.get(opts, :target_port, 5514)

    GenServer.call(__MODULE__, {:start, devices, rate, target_host, target_port}, :infinity)
  end

  @doc """
  Stops any running benchmark.
  """
  def stop_benchmark do
    GenServer.call(__MODULE__, :stop)
  end

  @doc """
  Returns the current benchmark status and telemetry.
  """
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    # Open high-performance UDP socket to share across all workers
    {:ok, socket} = :gen_udp.open(0, [:binary, active: false, sndbuf: 1024 * 1024])

    # Initialize lock-free CPU atomic counters for telemetry
    # Slot 1: sent_count
    # Slot 2: error_count
    atomics_ref = :atomics.new(2, [])
    :persistent_term.put(:boulder_atomics, atomics_ref)

    state = %{
      socket: socket,
      atomics: atomics_ref,
      devices: 0,
      rate: 0,
      target_host: "127.0.0.1",
      target_port: 5514,
      last_sent_count: 0,
      started_at: nil,
      ticker_ref: nil,
      is_running: false
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start, devices, rate, host_str, port}, _from, state) do
    # 1. Stop existing benchmark if running
    state = stop_active_benchmark(state)

    # 2. Reset atomics to zero
    :atomics.put(state.atomics, 1, 0)
    :atomics.put(state.atomics, 2, 0)

    # 3. Parse host
    host = parse_host(host_str)

    IO.puts("\n=== BOULDER BENCHMARK STARTING (LOCK-FREE ATOMICS) ===")
    IO.puts("Simulating #{devices} devices")
    IO.puts("Target Rate: #{rate} logs/sec per device (Total target: #{devices * rate}/sec)")
    IO.puts("Destination: #{host_str}:#{port}")
    IO.puts("========================================================\n")

    # 4. Spawn workers under DynamicSupervisor
    workers =
      for id <- 1..devices do
        spec = {DeviceWorker, [
          id: id,
          rate: rate,
          socket: :dedicated,
          target_host: host,
          target_port: port
        ]}
        {:ok, pid} = DynamicSupervisor.start_child(Boulder.DeviceSupervisor, spec)
        pid
      end

    # 5. Start 1-second interval ticker for console printing
    {:ok, ticker_ref} = :timer.send_interval(1000, self(), :tick)

    new_state = %{state |
      devices: length(workers),
      rate: rate,
      target_host: host_str,
      target_port: port,
      last_sent_count: 0,
      started_at: DateTime.utc_now(),
      ticker_ref: ticker_ref,
      is_running: true
    }

    {:reply, {:ok, length(workers)}, new_state}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    new_state = stop_active_benchmark(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    sent_count = :atomics.get(state.atomics, 1)
    error_count = :atomics.get(state.atomics, 2)
    reply = %{
      is_running: state.is_running,
      devices: state.devices,
      rate: state.rate,
      sent_count: sent_count,
      error_count: error_count,
      started_at: state.started_at
    }
    {:reply, reply, state}
  end

  # --- Info Telemetry & Tickers ---

  @impl true
  def handle_info(:tick, state) do
    elapsed = DateTime.diff(DateTime.utc_now(), state.started_at)
    current_sent = :atomics.get(state.atomics, 1)
    error_count = :atomics.get(state.atomics, 2)
    sent_this_second = current_sent - state.last_sent_count

    # Calculate actual speed and averages
    avg_speed = if elapsed > 0, do: div(current_sent, elapsed), else: current_sent

    # Print pretty metrics block
    IO.write("\r\e[K[Boulder] Running: #{elapsed}s | Active Devices: #{state.devices} | Outbound: #{sent_this_second}/sec (Avg: #{avg_speed}/sec) | Total Sent: #{current_sent}")

    if error_count > 0 do
      IO.write(" | Socket Errors: #{error_count}")
    end

    {:noreply, %{state | last_sent_count: current_sent}}
  end

  # --- Helper Functions ---

  defp stop_active_benchmark(state) do
    if state.is_running do
      IO.puts("\n\n=== BOULDER BENCHMARK STOPPING ===")
      if state.ticker_ref, do: :timer.cancel(state.ticker_ref)

      # Stop all children under our supervisor
      for child <- DynamicSupervisor.which_children(Boulder.DeviceSupervisor) do
        case child do
          {_id, pid, _type, _modules} -> DynamicSupervisor.terminate_child(Boulder.DeviceSupervisor, pid)
          _ -> :ok
        end
      end

      sent_count = :atomics.get(state.atomics, 1)
      IO.puts("All simulated devices terminated. Total logs sent: #{sent_count}")
      IO.puts("==================================\n")
    end

    %{state |
      devices: 0,
      rate: 0,
      last_sent_count: 0,
      started_at: nil,
      ticker_ref: nil,
      is_running: false
    }
  end

  defp parse_host(host) when is_binary(host) do
    case String.split(host, ".") do
      [a, b, c, d] ->
        {String.to_integer(a), String.to_integer(b), String.to_integer(c), String.to_integer(d)}
      _ ->
        String.to_charlist(host)
    end
  end
  defp parse_host(host), do: host
end
