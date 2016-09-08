defmodule Rackla.RouterGenServer do
  @moduledoc false
  
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    port = Application.get_env(:rackla, :port, 4000)
    port = if is_binary(port), do: String.to_integer(port), else: port

    Plug.Adapters.Cowboy.http(Router, [], port: port)
  end
end