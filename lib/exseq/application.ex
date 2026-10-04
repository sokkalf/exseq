defmodule ExSeq.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Each ExSeq handler gets its own Flusher, registered under the handler id.
    children = [
      {Registry, keys: :unique, name: ExSeq.Registry},
      {Task.Supervisor, name: ExSeq.TaskSupervisor},
      {DynamicSupervisor, name: ExSeq.FlusherSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExSeq.Supervisor)
  end
end
