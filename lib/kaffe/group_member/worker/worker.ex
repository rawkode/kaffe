defmodule Kaffe.Worker do
  @moduledoc """
  A worker is assigned a single partition across topics for the client. This is
  so we effectively serialize the processing of any single key across topics.

  Processing the message set is delegated to the configured message handler. It
  is responsible for any error handling. The message handler must define a
  `handle_messages` function (*note* the pluralization!) to accept a list of
  messages.

  The result of handle message is sent back to the subscriber.
  """

  require Logger

  def start_link(message_handler, subscriber_name, partition) do
    GenServer.start_link(__MODULE__, [message_handler, partition], name: name(subscriber_name, partition))
  end

  def init([message_handler, partition]) do
    Logger.info "event#starting=#{__MODULE__} partition=#{partition}"
    {:ok, %{message_handler: message_handler,
            partition: partition}}
  end

  def process_messages(pid, subscriber_pid, topic, partition, generation_id, messages) do
    GenServer.cast(pid, {:process_messages, subscriber_pid, topic, partition, generation_id, messages})
  end

  def handle_cast({:process_messages, subscriber_pid, topic, partition, generation_id, messages},
      %{message_handler: message_handler} = state) do

    :ok = apply(message_handler, :handle_messages, [messages])
    offset = Enum.reduce(messages, 0, &max(&1.offset, &2))
    subscriber().ack_messages(subscriber_pid, topic, partition, generation_id, offset)

    {:noreply, state}
  end

  def terminate(reason, _state) do
    Logger.info "event#terminate=#{inspect self()} reason=#{inspect reason}"
  end

  defp name(subscriber_name, partition) do
    :"partition_worker_#{subscriber_name}_#{partition}"
  end

  defp subscriber do
    Application.get_env(:kaffe, :subscriber_mod, Kaffe.Subscriber)
  end

end
