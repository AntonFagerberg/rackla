defmodule Rackla.RouterGenServer do
  @moduledoc false
  
  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_args) do
    port = 
      case Application.get_env(:rackla, :port, 4000) do
        port when is_binary(port) -> String.to_integer(port)
        port -> port
      end

    Plug.Adapters.Cowboy.http(Router, [], port: port)
  end
end
