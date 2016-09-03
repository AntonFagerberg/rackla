defmodule Rackla.Proxy do
  @moduledoc """
  `Rackla.Proxy` settings struct for using a proxy in outbound requests.

  Required:
  * `type` - `:socks5` (SOCKS5) or `:connect` (HTTP tunnel), default: `:socks5`.
  * `host` - Host, example: `"127.0.0.1"` or `"localhost"`, default: `"localhost"`.
  * `port` - Port, example: `8080`, default: `8080`.

  Optional:
  * `username` - Username for proxy, default: `nil`.
  * `password` - Password for proxy, default: `nil`.
  * `pool` - Define one pool per proxy if you wish to use several proxies 
    simultaneously, default: `nil`.
  """

  @type t :: %__MODULE__{
              type:     atom,
              host:     binary,
              port:     integer,
              username: binary,
              password: binary,
              pool:     atom}

  defstruct type:     :socks5,
            host:     "localhost",
            port:     8080,
            username: nil,
            password: nil,
            pool:     nil
end