defmodule Rackla.Response do
  @type t :: %__MODULE__{
              status: integer,
              headers: %{},
              body: binary}

  defstruct status:   nil, 
            headers:  %{},
            body:     ""
end