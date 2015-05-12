defmodule Rakkla do
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
    
    %Rakkla{producers: producers}
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
      
    %Rakkla{producers: [producers]}
  end
  
  def map(%Rakkla{producers: producers}, fun) when is_function(fun, 1) do
    new_producers = 
      Enum.map(producers, fn(producer) ->
        {:ok, new_producer} = 
          Task.start_link(fn ->
            try do
              send(producer, {self, :ready})
              
              response =
                receive do
                  {^producer, thing} -> fun.(thing)
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
    
    %Rakkla{producers: new_producers}
  end
  
  def flat_map(%Rakkla{producers: producers}, fun) do
    new_producers = 
      Enum.flat_map(producers, fn(producer) ->
        send(producer, {self, :ready})
        
        try do
          %Rakkla{producers: new_producers} =
            receive do
              {^producer, thing} -> 
                fun.(thing)
            end
          
          new_producers
        rescue
          exception -> 
            Logger.warn("Exception raised in flat_map: #{inspect(exception)}.")
            
            [
              Task.start_link(fn ->
                receive do
                  {consumer, :ready} ->
                    send(consumer, {self, :error, exception})
                end
              end)
            ]
        end
      end)
    
    %Rakkla{producers: new_producers}
  end
  
  def collect(%Rakkla{producers: producers}, options \\ []) do
    Enum.map(producers, fn(producer) -> 
      send(producer, {self, :ready})
      
      receive do
        {^producer, response} -> response
      end
    end)
  end
  
  def join(%Rakkla{producers: p1}, %Rakkla{producers: p2}) do
    %Rakkla{producers: p1 ++ p2}
  end
  
  defmacro response(%Rakkla{} = tasks, options \\ []) do
    quote do
      response_conn(unquote(tasks), var!(conn), unquote(options))
    end
  end
  
  def response_conn(%Rakkla{producers: producers}, conn, options \\ []) do
    if Dict.get(options, :compress, false) do
      response_compressed(producers, conn, options)
    else
      response_uncompressed(producers, conn, options)
    end
  end
  
  ### Private ###
  
  def response_uncompressed(%Rakkla{producers: producers}, conn, options \\ []) do
    conn
  end
  
  def response_compressed(%Rakkla{producers: producers}, conn, options \\ []) do
    responses =
      Enum.map(collect(producers), fn(response) ->
        unless is_binary(response), do: response = inspect(response)
        response
      end)
    
    chunk_status = 
      conn
      |> set_headers(Dict.get(options, :headers, %{}))
      |> send_chunked(Dict.get(options, :status, 200))
      |> chunk(Enum.join(responses))
      
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

defimpl Inspect, for: Rakkla do
  import Inspect.Algebra

  def inspect(rackla, opts) do
    concat ["#Rakkla<#{length(rackla.producers)}>"]
  end
end