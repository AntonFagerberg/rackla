defmodule Rackla do
  import Plug.Conn
  require Logger

  defstruct producers: []

  def request(requests, options \\ [])

  def request(requests, options) when is_list(requests) do
    producers =
      Enum.map(requests, fn(request) ->
        if is_binary(request), do: request = [url: request]

        {:ok, producer} =
          Task.start_link(fn ->
            hackney_request =
              :hackney.request(
                Dict.get(request, :method, :get),
                Dict.get(request, :url),
                Dict.get(request, :headers, %{}) |> Enum.into([]),
                Dict.get(request, :body, ""),
                [
                  insecure: Dict.get(options, :insecure, false),
                  connect_timeout: Dict.get(options, :connect_timeout, 5_000),
                  recv_timeout: Dict.get(options, :receive_timeout, 5_000)
                ]
              )

            case hackney_request do
              {:ok, status, headers, body_ref} ->
                case :hackney.body(body_ref) do
                  {:ok, body} ->
                    consumer = receive do
                      {pid, :ready} -> pid
                    end

                    response = %{status: status, headers: headers |> Enum.into(%{}), body: body}
                    send(consumer, {self, response})

                  {:error, atom} ->
                    warn_request(:closed)
                end

              {:error, {atom, _partial_body}} ->
                warn_request(atom)

              {:error, term} ->
                warn_request(term)
            end
          end)

        producer
      end)

    %Rackla{producers: producers}
  end

  def request(request, options) do
    request([request], options)
  end

  def just(thing) do
    {:ok, producers} =
      Task.start_link(fn ->
        consumer = receive do
          {pid, :ready} -> pid
        end

        send(consumer, {self, thing})
      end)

    %Rackla{producers: [producers]}
  end

  def map(%Rackla{producers: producers}, fun) when is_function(fun, 1) do
    new_producers =
      Enum.map(producers, fn(producer) ->
        {:ok, new_producer} =
          Task.start_link(fn ->
            try do
              send(producer, {self, :ready})

              response =
                receive do
                  {^producer, %Rackla{} = nested_producers} ->
                    responses = map(nested_producers, fun)

                  {^producer, thing} ->
                    response = fun.(thing)
                end

              consumer = receive do
                {pid, :ready} -> pid
              end

              send(consumer, {self, response})
            rescue
              exception ->
                Logger.warn("Exception raised in map: #{inspect(exception)}.")

                consumer = receive do
                  {pid, :ready} -> pid
                end

                send(consumer, {self, :error, exception})
            end
          end)

        new_producer
      end)

    %Rackla{producers: new_producers}
  end

  def flat_map(%Rackla{producers: producers}, fun) do
    new_producers =
      Enum.map(producers, fn(producer) ->
        {:ok, new_producer} =
          Task.start_link(fn ->
            try do
              send(producer, {self, :ready})

              %Rackla{producers: new_producers} =
                receive do
                  {^producer, %Rackla{} = nested_producers} ->
                    flat_map(nested_producers, fun)

                  {^producer, thing} ->
                    fun.(thing)
                end

              receive do
                {consumer, :ready} ->
                  send(consumer, {self, %Rackla{producers: new_producers}})
              end
            rescue
              exception ->
                Logger.warn("Exception raised in flat_map: #{inspect(exception)}.")

                receive do
                  {consumer, :ready} ->
                    send(consumer, {self, :error, exception})
                end
            end
          end)

          new_producer
      end)

    %Rackla{producers: new_producers}
  end

  def reduce(), do: :ok #todo

  def collect(%Rackla{producers: producers}, options \\ []) do
    [single_response | rest] = all_responses =
      Enum.flat_map(producers, fn(producer) ->
        send(producer, {self, :ready})

        receive do
          {^producer, %Rackla{} = nested_producers} ->
            collect(nested_producers)

          {^producer, response} ->
            [response]
        end
      end)

    if rest == [], do: single_response, else: all_responses
  end

  def join(%Rackla{producers: p1}, %Rackla{producers: p2}) do
    %Rackla{producers: p1 ++ p2}
  end

  defmacro response(%Rackla{} = tasks, options \\ []) do
    quote do
      response_conn(unquote(tasks), var!(conn), unquote(options))
    end
  end

  def response_conn(%Rackla{producers: producers}, conn, options \\ []) do
    if Dict.get(options, :compress, false) do
      response_compressed(producers, conn, options)
    else
      response_uncompressed(producers, conn, options)
    end
  end

  ### Private ###

  def response_uncompressed(%Rackla{} = producers, conn, options \\ []) do
    unless (conn.state == :chunked) do
      conn =
        conn
        |> set_headers(Dict.get(options, :headers, %{}))
        |> send_chunked(Dict.get(options, :status, 200))
    end

    prepare_chunks(producers)
    |> send_chunks(conn)
  end

  def send_chunks([], conn), do: conn

  def send_chunks(producers, conn) when is_list(producers) do
    receive do
      {producer, thing} ->
        unless is_binary(thing), do: thing = inspect(thing)
        case chunk(conn, thing) do
          {:ok, new_conn} ->
            send_chunks(List.delete(producers, producer), conn)

          {:error, reason} ->
            # Todo, kill all producers
            warn_response(reason)
            conn
        end
    end
  end

  def prepare_chunks(%Rackla{producers: producers}) do
    Enum.flat_map(producers, fn(producer) ->
      case producer do
        %Rackla{} = nested_producers ->
          prepare_chunks(nested_producers)

        pid ->
          send(pid, {self, :ready})
          [pid]
      end
    end)
  end

  def response_compressed(%Rackla{producers: producers}, conn, options \\ []) do
    compressed_response =
      Enum.map(collect(producers), fn(response) ->
        unless is_binary(response), do: response = inspect(response)
        response
      end)
      |> Enum.join
      |> :zlib.gzip

    chunk_status =
      conn
      |> set_headers(Dict.get(options, :headers, %{}))
      |> send_chunked(Dict.get(options, :status, 200))
      |> chunk(compressed_response)

    case chunk_status do
      {:ok, new_conn} ->
        new_conn

      {:error, reason} ->
        warn_response(reason)
        conn
    end
  end

  defp set_headers(conn, headers) do
    Enum.reduce(headers, conn, fn({key, value}, conn) ->
      put_resp_header(conn, key, value)
    end)
  end

  defp warn_response(reason), do: Logger.error("HTTP response error: #{inspect(reason)}")

  defp warn_request(reason) do
    Logger.warn("HTTP request error: #{inspect(reason)}")

    consumer = receive do
      {pid, :ready} -> pid
    end

    send(self, {:error, reason})
  end
end

defimpl Inspect, for: Rackla do
  import Inspect.Algebra

  def inspect(rackla, opts) do
    concat ["#Rackla<#{length(rackla.producers)}>"]
  end
end