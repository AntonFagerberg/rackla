defmodule Rackla.Application do
  @moduledoc false

  use Application

  def main(_args) do
    :timer.sleep(:infinity)
  end

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    children = [
      # Define workers and child supervisors to be supervised
      worker(Rackla.RouterGenServer, [])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Rackla.Supervisor]
    Supervisor.start_link(children, opts)
  end
end