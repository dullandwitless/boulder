defmodule Boulder.DeviceWorker do
  @moduledoc """
  A GenServer representing a simulated syslog device.
  Sends messages to the target IP/port using a shared UDP socket.
  Uses lock-free `:atomics` CPU counters for near-zero-overhead performance aggregation.
  """
  use GenServer

  alias Boulder.SyslogGenerator

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    hostname = Keyword.get(opts, :hostname) || "device-#{String.pad_leading(Integer.to_string(id), 4, "0")}.boulder.local"
    rate = Keyword.get(opts, :rate, 1) # logs per second
    socket =
      case Keyword.get(opts, :socket) do
        nil ->
          {:ok, s} = :gen_udp.open(0, [:binary, active: false, sndbuf: 1024 * 1024])
          s
        :dedicated ->
          {:ok, s} = :gen_udp.open(0, [:binary, active: false, sndbuf: 1024 * 1024])
          s
        s ->
          s
      end

    target_host = Keyword.get(opts, :target_host, {127, 0, 0, 1})
    target_port = Keyword.get(opts, :target_port, 5514)

    # Retrieve the persistent lock-free atomics counter reference
    atomics_ref = :persistent_term.get(:boulder_atomics)

    # Calculate timer interval and burst size to prevent overloading Erlang timers.
    # If a worker needs to send > 100 logs/sec (interval < 10ms), we send in bursts
    # every 10ms to keep timer CPU overhead near zero.
    {interval, burst_size} =
      cond do
        rate <= 0 ->
          {:infinite, 0}
        rate >= 100 ->
          # Send in bursts every 10ms
          {10, div(rate, 100)}
        true ->
          # Regular interval
          {round(1000 / rate), 1}
      end

    state = %{
      id: id,
      hostname: hostname,
      rate: rate,
      socket: socket,
      target_host: target_host,
      target_port: target_port,
      interval: interval,
      burst_size: burst_size,
      atomics_ref: atomics_ref,
      sent_count: 0
    }

    if interval != :infinite do
      # Add startup jitter (0 to 1000ms) so all processes don't fire at once
      jitter = :rand.uniform(1000)
      Process.send_after(self(), :tick, jitter)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    # Send the logs in burst
    sent = send_burst(state)

    # Schedule the next tick
    Process.send_after(self(), :tick, state.interval)

    # Count telemetry locally
    {:noreply, %{state | sent_count: state.sent_count + sent}}
  end

  # Helper to send multiple messages in a burst
  defp send_burst(%{burst_size: 0}), do: 0
  defp send_burst(state) do
    Enum.reduce(1..state.burst_size, 0, fn _, acc ->
      packet = SyslogGenerator.generate(hostname: state.hostname)
      case :gen_udp.send(state.socket, state.target_host, state.target_port, packet) do
        :ok ->
          # Lock-free increment of outbound logs sent (index 1)
          :atomics.add(state.atomics_ref, 1, 1)
          acc + 1
        {:error, _reason} ->
          # Lock-free increment of transmission errors (index 2)
          :atomics.add(state.atomics_ref, 2, 1)
          acc
      end
    end)
  end
end
