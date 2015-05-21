defmodule Rackla.Request do
  @moduledoc """
  `Rackla.Request` is the struct used when doing advanced HTTP requests.

  Required:
  * `url` - The URL to call in the HTTP request.

  Optional:
  * `method` - HTTP verb, default: `:get`.
  * `headers` - HTTP request headers, default: `%{}`.
  * `body` - HTTP request body (payload), default: `""`.
  * `options` - HTTP request specific options (see options below). These will
  overwrite global options.

  Options:
  * `:connect_timeout` - Connection timeout limit (ms), default: `5_000`.
  * `:receive_timeout` - Receive timeout limit (ms), default: `5_000`.
  * `:insecure` - If true, SSL certificates will not be checked, default: `false`.
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