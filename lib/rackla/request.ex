defmodule Rackla.Request do
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