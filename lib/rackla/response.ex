defmodule Rackla.Response do
  defstruct status: nil, headers: %{}, body: "", meta: %{}, error: nil
  @type t :: %Rackla.Response{status: integer, headers: %{}, body: binary, meta: %{}, error: atom}
end