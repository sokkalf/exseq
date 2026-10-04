defmodule ExSeq.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    config = Application.get_env(:logger, ExSeq, [])

    children = [
      {Task.Supervisor, name: ExSeq.TaskSupervisor},
      {ExSeq.Flusher, config}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExSeq.Supervisor)
  end
end
