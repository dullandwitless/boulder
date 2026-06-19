defmodule Boulder do
  @moduledoc """
  `Boulder` is a high-performance syslog generator companion application for benchmarking `SYSiphus`.
  """

  @doc """
  Starts a syslog benchmark with the specified configuration.

  Options:
    - `:devices` (integer) - Number of simulated devices to spawn. Defaults to 100.
    - `:rate` (integer) - Logs per second per device. Defaults to 10.
    - `:target_host` (string) - Receiver IP address. Defaults to "127.0.0.1".
    - `:target_port` (integer) - Receiver UDP port. Defaults to 5514.

  Example:
      # Spawn 1000 devices sending 20 logs/sec each (total 20k logs/sec)
      Boulder.start_benchmark(devices: 1000, rate: 20)
  """
  def start_benchmark(opts \\ []) do
    Boulder.Controller.start_benchmark(opts)
  end

  @doc """
  Stops the currently running benchmark and cleans up all active device processes.
  """
  def stop_benchmark do
    Boulder.Controller.stop_benchmark()
  end

  @doc """
  Returns current benchmark metrics.
  """
  def status do
    Boulder.Controller.status()
  end
end
