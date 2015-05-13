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
                Dict.get(request, :url, ""),
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
                    
                    response = 
                      if Dict.get(options, :full, false) do
                        %{status: status, headers: headers |> Enum.into(%{}), body: body}
                      else 
                        body
                      end

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
  
  def just_list(things) when is_list(things) do
    things
    |> Enum.map(&just/1)
    |> Enum.reduce(&join/2)
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

                send(consumer, {self, {:error, exception}})
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

              %Rackla{} = new_producers =
                receive do
                  {^producer, %Rackla{} = nested_producers} ->
                    flat_map(nested_producers, fun)

                  {^producer, thing} ->
                    fun.(thing)
                end
                
              receive do
                {consumer, :ready} ->
                  send(consumer, {self, new_producers})
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

  def reduce(%Rackla{} = rackla, fun) when is_function(fun, 2) do
    {:ok, new_producer} =
      Task.start_link(fn ->
        response = reduce_recursive(rackla, fun)
        
        receive do
          {consumer, :ready} -> send(consumer, {self, response})
        end
      end)
      
    %Rackla{producers: [new_producer]}
  end
  
  def reduce(%Rackla{} = rackla, acc, fun) when is_function(fun, 2) do
    {:ok, new_producer} =
      Task.start_link(fn ->
        response = reduce_recursive(rackla, acc, fun)
        
        receive do
          {consumer, :ready} -> send(consumer, {self, response})
        end
      end)
      
    %Rackla{producers: [new_producer]}
  end
  
  defp reduce_recursive(%Rackla{producers: producers}, fun) do
    [producer | tail_producers] = producers
    send(producer, {self, :ready})
    
    acc =
      receive do
        {^producer, %Rackla{} = nested_producers} ->
          reduce(nested_producers, fun)
        
        {^producer, thing} -> thing
      end

    reduce_recursive(%Rackla{producers: tail_producers}, acc, fun)
  end
  
  defp reduce_recursive(%Rackla{producers: producers}, acc, fun) do
    Enum.reduce(producers, acc, fn(producer, acc) ->
      send(producer, {self, :ready})
      
      receive do
        {^producer, %Rackla{} = nested_producers} ->
          reduce_recursive(nested_producers, acc, fun)
          
        {^producer, thing} ->
          fun.(thing, acc)
      end
    end)
  end

  def collect(%Rackla{} = rackla, options \\ []) do
    [single_response | rest] = all_responses = collect_recursive(rackla)
    if rest == [], do: single_response, else: all_responses
  end
  
  defp collect_recursive(%Rackla{producers: producers}, options \\ []) do
    Enum.flat_map(producers, fn(producer) ->
      send(producer, {self, :ready})

      receive do
        {^producer, %Rackla{} = nested_producers} ->
          collect_recursive(nested_producers)

        {^producer, response} ->
          [response]
      end
    end)
  end

  def join(%Rackla{producers: p1}, %Rackla{producers: p2}) do
    %Rackla{producers: p1 ++ p2}
  end

  defmacro response(tasks, options \\ []) do
    quote do
      var!(conn) = response_conn(unquote(tasks), var!(conn), unquote(options))
    end
  end

  def response_conn(%Rackla{} = rackla, conn, options \\ []) do
    if Dict.get(options, :compress, false) || Dict.get(options, :json, false) || Dict.get(options, :sync, false) do
      response_sync(rackla, conn, options)
    else
      response_async(rackla, conn, options)
    end
  end

  ### Private ###

  defp response_async(%Rackla{} = producers, conn, options \\ []) do
    unless (conn.state == :chunked) do
      conn =
        conn
        |> set_headers(Dict.get(options, :headers, %{}))
        |> send_chunked(Dict.get(options, :status, 200))
    end

    prepare_chunks(producers)
    |> send_chunks(conn)
  end
  
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

  defp send_chunks([], conn), do: conn

  defp send_chunks(producers, conn) when is_list(producers) do
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
            %Rackla{} = nested_rackla ->
              send_chunks(remaining_producers ++prepare_chunks(nested_rackla), conn)
            
            _ ->
              unless is_binary(thing), do: thing = inspect(thing)
              
              case chunk(conn, thing) do
                {:ok, new_conn} ->
                  send_chunks(remaining_producers, conn)

                {:error, reason} ->
                  warn_response(reason)
                  conn
              end
          end
        end
    end
  end
  
  defp make_json(%Rackla{} = rackla) do
    response = collect(rackla)
    
    cond do
      is_list(response) ->
        Enum.map(response, fn(thing) ->
          case Poison.decode(thing) do
            {:ok, decoded} -> decoded
            _ -> thing
          end
        end)
        |> Poison.encode
      
      true ->
        case Poison.decode(response) do
          {:ok, decoded} -> response
          true -> Poison.encode(response)
        end
    end
  end

  defp response_sync(%Rackla{} = rackla, conn, options \\ []) do
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

    send(consumer, {self, {:error, reason}})
  end
end

defimpl Inspect, for: Rackla do
  import Inspect.Algebra

  def inspect(rackla, opts) do
    concat ["#Rackla<#{length(rackla.producers)}>"]
  end
end