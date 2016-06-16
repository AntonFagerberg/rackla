defmodule Rackla.Request do
  @moduledoc """
  `Rackla.Request` is the struct used when executing advanced HTTP requests.

  Required:
  * `url` - The URL to call in the HTTP request.

  Optional:
  * `method` - HTTP verb, default: `:get`.
  * `headers` - HTTP request headers, default: `%{}`.
  * `body` - HTTP request body (payload), default: `""`.
  * `options` - HTTP request specific options (see options below). These will
  overwrite global options.

  Options:
  * `:full` - If set to true, the `Rackla` type will contain a `Rackla.Response`
  struct with the status code, headers and body (payload), global default: 
  false.
  * `:connect_timeout` - Connection timeout limit in milliseconds, global 
  default: `5_000`.
  * `:receive_timeout` - Receive timeout limit in milliseconds, global default: 
  `5_000`.
  * `:insecure` - If true, SSL certificates will not be checked, global default: 
  `false`.
  * `:follow_redirect` - If set to true, Rackla will follow redirects, 
  default: `false`.
  """

  @type t :: %__MODULE__{
              method:   atom,
              url:      binary,
              headers:  %{},
              body:     binary,
              options:  %{}}

  defstruct method:   :get,
            url:      "",
            headers:  %{},
            body:     "",
            options:  %{}
end