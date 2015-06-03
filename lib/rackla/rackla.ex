defmodule Rackla do
  @moduledoc Regex.replace(~r/```(elixir|json)(\n|.*)```/rs, File.read!("README.md"), 
  fn(_, _, code) -> Regex.replace(~r/^/m, code, "    ") end)
  
  import Plug.Conn
  require Logger

  @type t :: %__MODULE__{producers: [pid | t]}
  defstruct producers: []

  @doc """
  Takes a single string (URL) or a `Rackla.Request` struct and  executes a HTTP 
  request to the defined server. You can, by using the  `Rackla.Request` struct,
  specify more advanced options for your request such  as which HTTP verb to use
  but also individual connection timeout limits etc.  You can also call this 
  function with a list of strings or `Rackla.Request` structs in order to 
  perform multiple requests concurrently.
  
  This function will return a `Rackla` type which will contain the results 
  from the request(s) once available or an `:error` tuple in case of failures
  such non-responding servers or DNS lookup failures. Per default, on success, it 
  will only contain the response payload but the entire response can be used by 
  setting the option `:full` to true.

  Options:
   * `:full` - If set to true, the `Rackla` type will contain a `Rackla.Response`
   struct with the status code, headers and body (payload), default: false.
   * `:connect_timeout` - Connection timeout limit in milliseconds, default: 
   `5_000`.
   * `:receive_timeout` - Receive timeout limit in milliseconds, default: 
   `5_000`.
   * `:insecure` - If set to true, SSL certificates will not be checked, 
   default: `false`.
   
  If you specify any options in a `Rackla.Request` struct, these will overwrite
  the options passed to the `request` function for that specific request.
  """
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
                    
                    global_full = Dict.get(options, :full, false)
                    
                    response =
                      if Dict.get(request_options, :full, global_full) do
                        %Rackla.Response{status: status, headers: headers |> Enum.into(%{}), body: body}
                      else
                        body
                      end

                    send(consumer, {self, {:ok, response}})

                  {:error, reason} ->
                    warn_request(reason)
                end

              {:error, {reason, _partial_body}} ->
                warn_request(reason)

              {:error, reason} ->
                warn_request(reason)
            end
          end)

        producer
      end)

    %Rackla{producers: producers}
  end

  def request(request, options) do
    request([request], options)
  end

  @doc """
  Takes any type an encapsulates it in a `Rackla` type.
  
  Example:
      Rackla.just([1,2,3]) |> Rackla.map(&IO.inspect/1)
      [1, 2, 3]
  """
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

  @doc """
  Takes a list of and encapsulates each of the containing elements separately 
  in a `Rackla` type.
  
  Example:
      Rackla.just_list([1,2,3]) |> Rackla.map(&IO.inspect/1)
      3
      2
      1
  """
  @spec just_list([any]) :: t
  def just_list(things) when is_list(things) do
    things
    |> Enum.map(&just/1)
    |> Enum.reduce(&(join &2, &1))
  end

  @doc """
  Returns a new `Rackla` type, where each encapsulated item is the result of 
  invoking `fun` on each corresponding encapsulated item.
  
  Example:
      Rackla.just_list([1,2,3]) |> Rackla.map(fn(x) -> x * 2 end) |> Rackla.collect
      [2, 4, 6]
  """
  @spec map(t, (any -> any)) :: t
  def map(%Rackla{producers: producers}, fun) when is_function(fun, 1) do
    new_producers =
      Enum.map(producers, fn(producer) ->
        {:ok, new_producer} =
          Task.start_link(fn ->
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
          end)

        new_producer
      end)

    %Rackla{producers: new_producers}
  end

  @doc """
  Takes a `Rackla` type, applies the specified function to each of the 
  elements encapsulated in it and returns a new `Rackla` type with the 
  results. The given function must return a `Rackla` type.
  
  This function is useful when you want to create a new request pipeline based
  on the results of a previous request. In those cases, you can use 
  `Rackla.flat_map` to access the response from a request and call 
  `Rackla.request` inside the function since `Rackla.request` returns a 
  `Rackla` type.
  
  Example:
      Rackla.just_list([1,2,3]) |> Rackla.flat_map(fn(x) -> Rackla.just(x * 2) end) |> Rackla.collect
      [2, 4, 6]
  """
  @spec flat_map(t, (any -> t)) :: t
  def flat_map(%Rackla{producers: producers}, fun) do
    new_producers =
      Enum.map(producers, fn(producer) ->
        {:ok, new_producer} =
          Task.start_link(fn ->
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
          end)

          new_producer
      end)

    %Rackla{producers: new_producers}
  end

  @doc """
  Invokes `fun` for each element in the `Rackla` type passing that element and
  the accumulator `acc` as arguments. `fun`s return value is stored in `acc`. The 
  first element of the collection is used as the initial value of `acc`. Returns 
  the accumulated value inside a `Rackla` type.
  
  Example:
      Rackla.just_list([1,2,3]) |> Rackla.reduce(fn (x, acc) -> x + acc end) |> Rackla.collect
      6
  """
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

  @doc """
  Invokes `fun` for each element in the `Rackla` type passing that element and
  the accumulator `acc` as arguments. fun's return value is stored in `acc`.  
  Returns  the accumulated value inside a `Rackla` type.
  
  Example:
      Rackla.just_list([1,2,3]) |> Rackla.reduce(10, fn (x, acc) -> x + acc end) |> Rackla.collect
      16
  """
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
  
  @doc """
  Returns the element encapsulated inside a `Rackla` type, or a list of 
  elements in case the `Rackla` type contains many elements.
  
  Example:
      Rackla.just_list([1,2,3]) |> Rackla.collect
      [1,2,3]
  """
  @spec collect(t) :: [any] | any
  def collect(%Rackla{} = rackla) do
    [single_response | rest] = list_responses = collect_recursive(rackla)
    if rest == [], do: single_response, else: list_responses
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

  @doc """
  Returns a new `Rackla` type by joining the encapsulated elements from two
  `Rackla` types.
  
  Example:
      Rackla.join(Rackla.just(1), Rackla.just(2)) |> Rackla.collect
      [1, 2]
  """
  @spec join(t, t) :: t
  def join(%Rackla{producers: p1}, %Rackla{producers: p2}) do
    %Rackla{producers: p1 ++ p2}
  end

  @doc """
  Converts a `Rackla` type to a HTTP response and send it to the client by
  using `Plug.Conn`. The `Plug.Conn` will be taken implicitly by looking for a 
  variable named `conn`. If you want to specify which `Plug.Conn` to use, you 
  can use `Rackla.response_conn`.
  
  Strings will be sent as is to the client. If the `Rackla` type contains any 
  other type such as a list, it will be converted into a string by using `inspect`
  on it. You can also convert Elixir data types to JSON format by setting the
  option `:json` to true.
  
  Using this macro is the same as writing:
      conn = response_conn(rackla, conn, options)
  
  Options:
   * `:compress` - Compresses the response by applying a gzip compression to it.
   When this option is used, the entire response has to be sent in one chunk. 
   You can't reuse the `conn` to send any more data after `Rackla.response` with
   `:compress` set to `true` has been invoked. When set to `true`, Rackla will
   check the request header `content-encoding` to make sure the client accepts
   gzip responses. If you want to respond with gzip without checking the
   request headers, you can set `:compress` to `:force`.
   * `:json` - If set to true, the encapsulated elements will be converted into
   a JSON encoded string before they are sent to the client. This will also set
   the header "content-type" to the appropriate "application/json; charset=utf-8".
  """
  defmacro response(rackla, options \\ []) do
    quote do
      var!(conn) = response_conn(unquote(rackla), var!(conn), unquote(options))
    end
  end

  @doc """
  See documentation for `Rackla.response`.
  """
  @spec response_conn(t, Plug.Conn.t, Dict.t) :: Plug.Conn.t
  def response_conn(%Rackla{} = rackla, conn, options \\ []) do
    cond do
      Dict.get(options, :compress, false) || Dict.get(options, :json, false) ->
        response_sync(rackla, conn, options)
      Dict.get(options, :sync, false) ->
        response_sync_chunk(rackla, conn, options)
      true ->
        response_async(rackla, conn, options)
    end
  end

  @spec response_async(t, Plug.Conn.t, Dict.t) :: Plug.Conn.t
  defp response_async(%Rackla{} = producers, conn, options) do
    conn = prepare_conn(conn, Dict.get(options, :status, 200), Dict.get(options, :headers, %{}))

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

            error ->
              send_thing.(error, remaining_producers, conn)
          end
        end
    end
  end
  
  @spec prepare_conn(Plug.Conn.t, Integer, Dict.t) :: Plug.Conn.t
  defp prepare_conn(conn, status, headers) do
    if (conn.state == :chunked) do
      conn
    else
      conn
      |> set_headers(headers)
      |> send_chunked(status)
    end
  end
  
  @spec response_sync_chunk(t, Plug.Conn.t, Dict.t) :: Plug.Conn.t
  defp response_sync_chunk(%Rackla{} = rackla, conn, options) do
    conn = prepare_conn(conn, Dict.get(options, :status, 200), Dict.get(options, :headers, %{}))
    
    Enum.reduce(prepare_chunks(rackla), conn, fn(pid, conn) ->
      receive do
        {^pid, {:rackla, nested_rackla}} ->
          response_sync_chunk(nested_rackla, conn, options)
          
        {^pid, thing} ->
          if elem(thing, 0) == :ok, do: thing = elem(thing, 1)
          unless is_binary(thing), do: response = inspect(thing)
          
          case chunk(conn, thing) do
            {:ok, new_conn} ->
              new_conn
      
            {:error, reason} ->
              warn_response(reason)
              conn
          end
      end
    end)
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
        
        compress = Dict.get(options, :compress, false)
        
        if compress do
          allow_gzip = 
            Plug.Conn.get_req_header(conn, "accept-encoding")
            |> Enum.flat_map(fn(encoding) ->
              String.split(encoding, ",", trim: true)
              |> Enum.map(&String.strip/1)
            end)
            |> Enum.any?(&(Regex.match?(~r/(^(\*|gzip)(;q=(1$|1\.0{1,3}$|0\.[1-9]{1,3}$)|$))/, &1)))
          
          if allow_gzip || compress == :force do
            response_binary = :zlib.gzip(response_binary)
            headers = Dict.merge(headers, %{"content-encoding" => "gzip"})
          end
        end

        if Dict.get(options, :json, false) do
          conn = put_resp_content_type(conn, "application/json")
        end

        chunk_status =
          prepare_conn(conn, Dict.get(options, :status, 200), headers)
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

  def inspect(rackla, _opts) do
    concat ["#Rackla<>"]
  end
end