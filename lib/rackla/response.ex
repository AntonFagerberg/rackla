defmodule Rackla.Response do
  @moduledoc """
  `Rackla.Response` is the struct returned when successfully getting an HTTP
  response and the `request` function was called with the option `:full` set to
  `true`.

  Fields:
  * `:status` - Numeric HTTP status code (such as 200 for OK).
  * `:headers` - Map with HTTP response headers.
  * `:body` - HTTP response body (payload):
  """
  @type t :: %__MODULE__{
              status: integer,
              headers: %{},
              body: binary}

  defstruct status:   nil,
            headers:  %{},
            body:     ""
end