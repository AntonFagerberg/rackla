defmodule Rackla do
  import Plug.Conn
  require Logger

  @type t :: %__MODULE__{producers: [pid | t]}
  defstruct producers: []

  @spec request(String.t | Rackla.Request.t | [String.t] | [Rackla.Request.t], Dict.t) :: t
  def request(requests, options \\ [])

  def request(requests, options) when is_list(requests) do
    producers =
      Enum.map(requests, fn(request) ->
        if is_binary(request), do: request = %Rackla.Request{url: request}

        {:ok, producer} =
          Task.start_link(fn ->
            request_options = Map.get(request, :options, [])
            global_insecure = Dict.get(options, :insecure, false)
            global_connect_timeout = Dict.get(options, :connect_timeout, 5_000)
            global_receive_timeout = Dict.get(options, :receive_timeout, 5_000)

            hackney_request =
              :hackney.request(
                Map.get(request, :method, :get),
                Map.get(request, :url, ""),
                Map.get(request, :headers, %{}) |> Enum.into([]),
                Map.get(request, :body, ""),
                [
                  insecure: Dict.get(request_options, :insecure, global_insecure),
                  connect_timeout: Dict.get(request_options, :connect_timeout, global_connect_timeout),
                  recv_timeout: Dict.get(request_options, :receive_timeout, global_receive_timeout)
                ]
              )

            case hackney_request do
              {:ok, status, headers, body_ref} ->
                case :hackney.body(body_ref) do
                  {:ok, body} ->
                    consumer = receive do
                      {pid, :ready} -> pid
                    end

                    response =
                      if Dict.get(options, :full, false) do
                        %Rackla.Response{status: status, headers: headers |> Enum.into(%{}), body: body}
                      else
                        body
                      end

                    send(consumer, {self, {:ok, response}})

                  {:error, atom} ->
                    warn_request(atom)
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

  @spec just(any | [any]) :: t
  def just(thing) do
    {:ok, producers} =
      Task.start_link(fn ->
        consumer = receive do
          {pid, :ready} -> pid
        end

        send(consumer, {self, {:ok, thing}})
      end)

    %Rackla{producers: [producers]}
  end

  @spec just_list([any]) :: t
  def just_list(things) when is_list(things) do
    things
    |> Enum.map(&just/1)
    |> Enum.reduce(&join/2)
  end

  @spec map(t, (any -> any)) :: t
  def map(%Rackla{producers: producers}, fun) when is_function(fun, 1) do
    new_producers =
      Enum.map(producers, fn(producer) ->
        {:ok, new_producer} =
          Task.start_link(fn ->
            try do
              send(producer, {self, :ready})

              response =
                receive do
                  {^producer, {:rackla, nested_producers}} ->
                    {:rackla, map(nested_producers, fun)}

                  {^producer, {:ok, thing}} ->
                    {:ok, fun.(thing)}

                  {^producer, error} ->
                    {:ok, fun.(error)}
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

                send(consumer, {self, {:error, exception}})
            end
          end)

        new_producer
      end)

    %Rackla{producers: new_producers}
  end

  @spec flat_map(t, (any -> t)) :: t
  def flat_map(%Rackla{producers: producers}, fun) do
    new_producers =
      Enum.map(producers, fn(producer) ->
        {:ok, new_producer} =
          Task.start_link(fn ->
            try do
              send(producer, {self, :ready})

              %Rackla{} = new_rackla =
                receive do
                  {^producer, {:rackla, nested_rackla}} ->
                    flat_map(nested_rackla, fun)

                  {^producer, {:ok, thing}} ->
                    fun.(thing)

                  {^producer, error} ->
                    fun.(error)
                end

              receive do
                {consumer, :ready} ->
                  send(consumer, {self, {:rackla, new_rackla}})
              end
            rescue
              exception ->
                Logger.warn("Exception raised in flat_map: #{inspect(exception)}.")

                receive do
                  {consumer, :ready} ->
                    send(consumer, {self, {:error, exception}})
                end
            end
          end)

          new_producer
      end)

    %Rackla{producers: new_producers}
  end

  @spec reduce(t, (any, any -> any)) :: t
  def reduce(%Rackla{} = rackla, fun) when is_function(fun, 2) do
    {:ok, new_producer} =
      Task.start_link(fn ->
        thing = reduce_recursive(rackla, fun)

        receive do
          {consumer, :ready} -> send(consumer, {self, {:ok, thing}})
        end
      end)

    %Rackla{producers: [new_producer]}
  end

  def reduce(%Rackla{} = rackla, acc, fun) when is_function(fun, 2) do
    {:ok, new_producer} =
      Task.start_link(fn ->
        thing = reduce_recursive(rackla, acc, fun)

        receive do
          {consumer, :ready} -> send(consumer, {self, {:ok, thing}})
        end
      end)

    %Rackla{producers: [new_producer]}
  end

  @spec reduce_recursive(t, (any, any -> any)) :: any
  defp reduce_recursive(%Rackla{producers: producers}, fun) do
    [producer | tail_producers] = producers
    send(producer, {self, :ready})

    acc =
      receive do
        {^producer, {:rackla, nested_producers}} ->
          reduce_recursive(nested_producers, fun)

        {^producer, {:ok, thing}} ->
          thing

        {^producer, error} ->
          error
      end

    reduce_recursive(%Rackla{producers: tail_producers}, acc, fun)
  end

  @spec reduce_recursive(t, any, (any, any -> any)) :: any
  defp reduce_recursive(%Rackla{producers: producers}, acc, fun) do
    Enum.reduce(producers, acc, fn(producer, acc) ->
      send(producer, {self, :ready})

      receive do
        {^producer, {:rackla, nested_producers}} ->
          reduce_recursive(nested_producers, acc, fun)

        {^producer, {:ok, thing}} ->
          fun.(thing, acc)

        {^producer, error} ->
          fun.(error, acc)
      end
    end)
  end

  @spec collect(t) :: [any] | any
  def collect(%Rackla{} = rackla) do
    [single_response | rest] = all_responses = collect_recursive(rackla)
    if rest == [], do: single_response, else: all_responses
  end

  @spec collect_recursive(t) :: [any]
  defp collect_recursive(%Rackla{producers: producers}) do
    Enum.flat_map(producers, fn(producer) ->
      send(producer, {self, :ready})

      receive do
        {^producer, {:rackla, nested_rackla}} ->
          collect_recursive(nested_rackla)

        {^producer, {:ok, thing}} ->
          [thing]

        {^producer, error} ->
          [error]
      end
    end)
  end

  @spec join(t, t) :: t
  def join(%Rackla{producers: p1}, %Rackla{producers: p2}) do
    %Rackla{producers: p1 ++ p2}
  end

  defmacro response(tasks, options \\ []) do
    quote do
      var!(conn) = response_conn(unquote(tasks), var!(conn), unquote(options))
    end
  end

  @spec response_conn(t, Plug.Conn.t, Dict.t) :: Plug.Conn.t
  def response_conn(%Rackla{} = rackla, conn, options \\ []) do
    if Dict.get(options, :compress, false) || Dict.get(options, :json, false) || Dict.get(options, :sync, false) do
      response_sync(rackla, conn, options)
    else
      response_async(rackla, conn, options)
    end
  end

  @spec response_async(t, Plug.Conn.t, Dict.t) :: Plug.Conn.t
  defp response_async(%Rackla{} = producers, conn, options) do
    unless (conn.state == :chunked) do
      conn =
        conn
        |> set_headers(Dict.get(options, :headers, %{}))
        |> send_chunked(Dict.get(options, :status, 200))
    end

    prepare_chunks(producers)
    |> send_chunks(conn)
  end

  @spec prepare_chunks(t) :: [pid]
  defp prepare_chunks(%Rackla{producers: producers}) do
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

  @spec send_chunks([pid], Plug.Conn.t) :: Plug.Conn.t
  defp send_chunks([], conn), do: conn

  defp send_chunks(producers, conn) when is_list(producers) do
    send_thing = fn(thing, remaining_producers, conn) ->
      unless is_binary(thing), do: thing = inspect(thing)

      case chunk(conn, thing) do
        {:ok, new_conn} ->
          send_chunks(remaining_producers, new_conn)

        {:error, reason} ->
          warn_response(reason)
          conn
      end
    end

    receive do
      {message_producer, thing} ->
        {remaining_producers, current_producer} =
          Enum.partition(producers, fn(pid) ->
            pid != message_producer
          end)

        if (current_producer == []) do
          send_chunks(producers, conn)
        else
          case thing do
            {:rackla, nested_rackla} ->
              send_chunks(remaining_producers ++ prepare_chunks(nested_rackla), conn)

            {:ok, thing} ->
              send_thing.(thing, remaining_producers, conn)

            {error} ->
              send_thing.(error, remaining_producers, conn)
          end
        end
    end
  end

  @spec response_sync(t, Plug.Conn.t, Dict.t) :: Plug.Conn.t
  defp response_sync(%Rackla{} = rackla, conn, options) do
    response = collect(rackla)

    response_encoded =
      if Dict.get(options, :json, false) do
        cond do
          is_list(response) ->
            Enum.map(response, fn(thing) ->
              if is_binary(thing) do
                case Poison.decode(thing) do
                  {:ok, decoded} -> decoded
                  _ -> thing
                end
              else
                thing
              end
            end)
            |> Poison.encode

          true ->
            if is_binary(response) do
              case Poison.decode(response) do
                {:error, _reason} -> Poison.encode(response)
                {:ok, _decoded} -> {:ok, response}
              end
            else
              Poison.encode(response)
            end
        end
      else
        cond do
          is_list(response) ->
            binary =
              Enum.map(response, fn(thing) ->
                unless is_binary(thing), do: thing = inspect(thing)
                thing
              end)
              |> Enum.join

            {:ok, binary}

          is_binary(response) ->
            {:ok, response}

          true ->
            {:ok, inspect(response)}
        end
      end

    case response_encoded do
      {:ok, response_binary} ->
        headers = Dict.get(options, :headers, %{})

        if Dict.get(options, :compress, false) do
          response_binary = :zlib.gzip(response_binary)
          headers = Dict.merge(headers, %{"Content-Encoding" => "gzip"})
        end

        if Dict.get(options, :json, false) do
          headers = Dict.merge(headers, %{"Content-Type" => "application/json"})
        end

        chunk_status =
          conn
          |> set_headers(headers)
          |> send_chunked(Dict.get(options, :status, 200))
          |> chunk(response_binary)

        case chunk_status do
          {:ok, new_conn} ->
            new_conn

          {:error, reason} ->
            warn_response(reason)
            conn
        end

      {:error, reason} ->
        Logger.error("Response decoding error: #{inspect(reason)}")
        conn
    end
  end

  @spec set_headers(Plug.Conn.t, Dict.t) :: Plug.Conn.t
  defp set_headers(conn, headers) do
    Enum.reduce(headers, conn, fn({key, value}, conn) ->
      put_resp_header(conn, key, value)
    end)
  end

  @spec warn_response(any) :: :ok
  defp warn_response(reason), do: Logger.error("HTTP response error: #{inspect(reason)}")

  @spec warn_request(any) :: :ok
  defp warn_request(reason) do
    Logger.warn("HTTP request error: #{inspect(reason)}")

    consumer = receive do
      {pid, :ready} -> pid
    end

    send(consumer, {self, {:error, reason}})

    :ok
  end
end

defimpl Inspect, for: Rackla do
  import Inspect.Algebra

  defp count(producers) do
    Enum.reduce(producers, 0, fn(item, acc) ->
      case item do
        %Rackla{producers: producers} -> count(producers)
        _ -> acc + 1
      end
    end)
  end

  def inspect(rackla, _opts) do
    concat ["#Rackla<#{count(rackla.producers)}>"]
  end
end