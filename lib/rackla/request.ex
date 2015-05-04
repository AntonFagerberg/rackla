defmodule Rackla.Request do
  defstruct method: :get, url: nil, headers: %{}, body: "", options: %{}, meta: %{}
  @type t :: %Rackla.Request{method: atom, url: binary, headers: %{}, body: binary, options: %{}, meta: %{}}
end