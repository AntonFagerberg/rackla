defmodule Mix.Tasks.Server do
  use Mix.Task
  
  @shortdoc "Starts applications and their servers"

  def run(_args) do
    Mix.Task.run "app.start", []
    unless iex_running?, do: :timer.sleep(:infinity)
  end

  defp iex_running? do
    Code.ensure_loaded?(IEx) && IEx.started?
  end
end