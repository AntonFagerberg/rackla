defmodule CrocodilePear do
  @moduledoc """
  CrocodilePear is library primarily used for building API-gateways. When we say API-gateway, we mean to proxy and potentially enhance the communication between servers and HTTP clients such as browsers by transforming the data. The communication can be enhanced by throwing away unnecessary data, concatenate requests or convert the data between different formats. 

  With CrocodilePear you can execute multiple HTTP-requests and transform them in any way you want---asynchronous end to end. The protocol used inside CrocodilePear is based on a list of Elixir processes which follows a defined communication protocol. By piping functions together and forming a pipeline, these processes can communicate independently (asynchronously) of each other to achieve good performance. 

  The protocol used between the Elixir process is by default abstracted away. By utilizing helper functions instead, the developer can gain the performance benefit without having to deal with any message passing. There is however nothing stopping the developers who want to tap directly in to the process messaging.

  CrocodilePear utilizes [Plug](https://github.com/elixir-lang/plug) to communicate with the clients over HTTP. Internally, it uses [Hackney](https://github.com/benoitc/hackney) to make HTTP requests and [Poison](https://github.com/devinus/poison) for dealing with JSON.
  
  ## Examples (with Plug)

  ### Simple request/response
  A simple proxy can be created by exposing an endpoint `/proxy` where we get the target url from the query string, example: `/proxy?www.example.com`. We can then create a simple pipeline by starting with the query-string, piping it to the request function which will make a GET request to the URL from the query-string and finally piping the result to the response function. The response function will then take the `conn`-struct from Plug and respond to the client.

        get "/proxy" do
          conn.query_string
          |> request
          |> response(conn)
        end

  ### Multiple requests
  In the same manner as the previous example, we can use the query-string to retrieve any number of request URLs. In this example, we take a list of URLs from the query string separated by the `|` character, for example: `/proxy/multi?www.example1.com|www.example2.com`.

      get "/proxy/multi" do
        String.split(conn.query_string, "|")
        |> request
        |> response(conn)
      end

  In this example, all requests are executed asynchronously and so the first request which is responding will be sent first to the client. The response is therefore indeterministic and the response body is just each individual response concatenated to one response. This is in most cases useless so let's continue and see what we can do to improve that.

  ### Concatenate JSON
  The function `concatenate_json` solves the problem from the previous example. When we get responses, especially out of order, we probably want to know which response belongs which request. Concatenate JSON will give us this and many more benefits. When piping to `concatenate_json`, all responses will be turned in to a JSON-list where each request has its own JSON-object containing the status-code, headers, body and a meta-field which developers can use to add additional information. By default, the meta-field will contain the requested URL so that all items easily can be identified.

      get "/proxy/multi/concat-json" do
        String.split(conn.query_string, "|")
        |> request
        |> concatenate_json
        |> response(conn)
      end

  If you're only interested in the body of the response, you can pass `body_only: true` to the `concatenate_json` function which will then discard all other data. Every item in the JSON-list is then just the body from the response.

  ### Transform
  The function `transform` is an abstraction which makes it easy to manipulate the responses asynchronously. Transform takes a single lambda-function as its only argument. The lambda-function in turn should take a response-map and must return a new response-map with the same keys. The response-map has four keys which can be accessed: `:meta`, `:status`, `:headers` and `:body`. As an example, we can look at the identity function (which does nothing):

      get "/proxy/transform/identity" do
        identity = fn(response) ->
          response
          |> Dict.update!(:status, fn(x) -> x end)
          |> Dict.update!(:headers, fn(x) -> x end)
          |> Dict.update!(:body, fn(x) -> x end)
          |> Dict.update!(:meta, fn(x) -> x end)
        end

        request(conn.query_string)
        |> transform(identity)
        |> response(conn)
      end

  The transform function works on a "per response" basis on any number of requests and is fully asynchronous.

  ### Collect response
  Sometimes you want to break out of the asynchronous behavior. In such cases, you can utilize the `collect_response` function. When `collect_response` is used, it will wait until all request has responded and collect all responses in a list. Each item in the list is a response-map with the keys `:status`, `:headers`, `:body` and `:meta`.


  ### Multiple pipelines
  It is important to point out that you can define multiple pipelines---either to be used in parallel or recursively. You may have two different collections of URLs which should be processed in different ways. This can be accomplished by creating two pipelines which are then concatenated:

      get "/multi/pipeline" do
        pipeline_1 = list_of_URLs_1 |> request |> transform(do_things_1)
        pipeline_2 = list_of_URLs_2 |> request |> transform(do_things_2)
        
        pipeline_1 ++ pipeline_2
        |> response(conn)
      end

  Using multiple pipelines in this fashion will process all requests asynchronously and respond in the same manner.

  In the same way, you can create recursive pipelines. The easiest way to do this is to start a new pipeline inside the lambda function used in the `transform` function. Just remember that the lambda-function used in `transform` must return a map so it is a good idea to use `collect_response` here to convert the internal pipeline to a map. Since the `transform`-function is executed asynchronously, the outer pipeline will not be affected when using `collect_response` in a pipeline inside a `transform` function.

  ### Advanced requests
  The function `request` can either take strings (URLs) which will then be transformed to a GET-request or you can specify a map with more advanced details. The request-map reads the following keys: `:url`, `:method` which defaults to `:get`, `:body` (request payload) which defaults to the empty string and `:headers` which defaults to an empty keyword-list. You can also enter any data you want into the `:meta` map by specifying it in the `request`-map.

  Note that the `request` function accepts any of the following data-types as its parameter:

  * String (single URL)
  * List of strings (multiple URLs)
  * Map (single request)
  * List of maps (multiple requests)

  ### Timers
  Timers can be used anywhere in the pipeline to log timestamps. The timers can be used between both synchronous and asynchronous functions to determine what happens on which moments in time. On synchronous functions, the log event will be called after the function call has completed---on asynchronous calls which follows the protocol defined by CrocodilePear, a log event will be triggered on every message between the Elixir processes.

      "https://api.instagram.com/v1/users/self/feed?count=50&access_token=" <> conn.query_string
      |> timer("Got URL")
      |> request
      |> timer("Executed request")
      |> collect_response
      |> timer("Collected response")
      |> Dict.get(:body)
      |> timer("Got body")
      |> Poison.decode!
      |> timer("Decoded JSON")
      |> Dict.get("data")
      |> timer("Extracted data")
      |> Enum.map(&(&1["images"]["standard_resolution"]["url"]))
      |> timer("Mapped image url")
      |> request
      |> timer("Executed request")
      |> transform(binary_to_img)
      |> timer("Added transform function")
      |> response(conn)
      |> timer("Responded to query")

  This will output information to `Logger.info`, example:

      14:02:46.800 [info]  {1427, 288566, 800037} [meta] (Added transform function) on #PID<0.519.0>
      14:02:46.800 [info]  {1427, 288566, 800160} [status] (Added transform function) on #PID<0.519.0>
      14:02:46.800 [info]  {1427, 288566, 800228} [headers] (Added transform function) on #PID<0.519.0>
      14:02:46.800 [info]  {1427, 288566, 800272} [chunk] (Added transform function) on #PID<0.519.0>
      14:02:46.800 [info]  {1427, 288566, 800317} [done] (Added transform function) on #PID<0.519.0>
      14:02:46.800 [info]  {1427, 288566, 800467} (Responded to query)

  The message consists of (with the Logger information excluded):

      {erlang timestamp} [message type] (optional label) Process Identifier

  ### Compression
  The response can be compressed by utilizing GZip. To enable compression, set `:compress` to `true` in the keyword-list argument in the `response` function.

      response(conn, compress: true)

  ### Decompression
  When performing requests to a back-end which replies with compressed data, you have to decompress it before processing it (unless you want to send it directly to the client). If the beck-end uses GZip-compression, then you can use the Zlib module in Erlang to decompress the body, for example by creating a `transform` lambda-function:

      transform(fn(resp) -> Dict.update!(resp, :body, &:zlib.gunzip/1) end)

  ### Working with JSON
  CrocodilePear uses [Poison](https://github.com/devinus/poison) for working with JSON internally. It is a great library which converts JSON-structures to Elixir-structures and vice versa. Poison can of course also be used in the end-points for transforming and manipulating JSON data in the pipeline.

  ### Working with XML (and other formats)
  There is currently no special XML support (or any other format except JSON). You can request data in any format over HTTP, process it with any third-party library and respond with it---but there are no built in helper functions such as the `concatenate_json` used for JSON.
  """
  
  import Plug.Conn
  require Logger
  
  @type requests  :: String.t | %{atom => String.t} | [String.t] | [%{atom => String.t}]
  @type producers :: pid | [pid]
  @type response  :: %{atom => String.t | Map.t}

  @doc """
  `request` is usually the beginning of a pipeline. It executes all
  HTTP requests concurrently and returns a list of Elixir PIDs (producers) which
  will respond as soon as a response is available.
  
  Args:
    * `requests` - String (URL), request `map` or list of strings or 
    request `map`(s).
    * `options` - Dict with additional options (see below).
    
  Options:
    * `:insecure` - Boolean whether to perform SSL connections without checking
    the certificate. Default: false.
    * `:connect_timeout` - Timeout for request in milliseconds. Default: 5_000.
    
  Keys which can be used in the request map:
    * `:url` - Request URL to call.
    * `:method` (optional) - HTTP verb. Default: `:get`.
    * `:body` (optional) - Payload data. Default: `""`.
    * `headers` (optional) - Header `map`. Default: `%{}`
  """
  @spec request(requests, Dict.t) :: [pid]
  def request(requests, options \\ [])
  
  def request(request, options) when is_bitstring(request) or is_map(request) do
    request([request], options)
  end

  def request(requests, options) when is_list(requests) do
    Enum.map(requests, fn(request_map) ->
      if is_binary(request_map), do: request_map = %{url: request_map}
      
      {:ok, producer} = 
        if (Dict.has_key?(request_map, :url)) do
          Task.start_link(fn ->
            case :hackney.request(
              Dict.get(request_map, :method, :get),
              Dict.fetch!(request_map, :url),
              Dict.get(request_map, :headers, []) |> Enum.into([]),
              Dict.get(request_map, :body, ""),
              [
                {:connect_timeout, Dict.get(options, :connect_timeout, 5_000)},
                {:recv_timeout, :infinity},
                :async,
                {:stream_to, self},
                {:insecure, Dict.get(options, :insecure, false)}
              ]
            ) do
              {:ok, id} ->
                consumer = receive do
                  { pid, :ready } -> pid
                end
                
                meta_map = Dict.get(request_map, :meta, %{})
                
                send(consumer, { self, :meta, Map.put(meta_map, :url, Dict.fetch!(request_map, :url)) })

                receive do
                  {:hackney_response, ^id, {:headers, headers}} ->
                    send(consumer, { self, :headers, Enum.into(headers, %{}) })
                    
                  {:hackney_response, ^id, {:error, reason}} ->
                    throw reason
                end

                receive do
                  {:hackney_response, ^id, {:status, code, _reason}} -> 
                    send(consumer, { self, :status, code })
                    
                  {:hackney_response, ^id, {:error, reason}} ->
                    throw reason
                end

                get_hackney_chunk(id, consumer)
                
              {:error, reason} ->
                consumer = receive do
                  { pid, :ready } -> pid
                end
                
                Logger.warn("HTTP request failure: #{reason}")
                
                send(consumer, { self, :status, Dict.get(request_map, :status, 500) })
                send(consumer, { self, :meta, %{error: reason} })
                send(consumer, { self, :headers, %{} })
                send(consumer, { self, :chunk, "" })
                send(consumer, { self, :done })
            end
          end)
        else
          Task.start_link(fn ->
            consumer = receive do
              { pid, :ready } -> pid
            end
            
            send(consumer, { self, :status, Dict.get(request_map, :status, 200) })
            send(consumer, { self, :meta, Dict.get(request_map, :meta, %{}) })
            send(consumer, { self, :headers, Dict.get(request_map, :headers, %{}) })
            send(consumer, { self, :chunk, Dict.get(request_map, :body, "") })
            send(consumer, { self, :done })
          end)
        end

      producer
    end)
  end

  @doc """
  `response` uses `conn` from Plug in order to transmit the responses from the 
  producers to the client over HTTP.
  
  If there is only one item in the `producers` list, that `producer`'s headers
  and status code will be added to the response per default if not already sent.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by CrocodilePear).
    * `conn` - Plug´s `conn` structure.
    * `options` - Options (see below). Default: %{}.
    
  Options:
    * `:compress` - boolean whether to gzip response or note. Default: false.
    * `:headers` - response headers (map). Default: [].
    * `:status` - HTTP response status code. Default: 200 (OK)
  """
  @spec response(producers, Conn.t, Dict.t) :: Conn.t
  def response(producers, conn, options \\ [])

  def response([producer], conn, options) do
    if (Dict.get(options, :compress, false)) do
      response_compressed(producer, conn, options)
    else
      send(producer, { self, :ready })

      set_response_headers = fn(conn, producer) ->
        receive do
          {^producer, :headers, response_headers} ->
            if (conn.state == :chunked) do
              conn
            else
              option_headers = Dict.get(options, :headers, %{})
              
              conn
              |> set_headers(response_headers)
              |> set_headers(option_headers)
            end
        end
      end

      set_response_status = fn(conn, producer) ->
        receive do
          {^producer, :status, status} -> 
            if (conn.state == :chunked) do
              conn
            else
              option_status = Dict.get(options, :status, status)
              send_chunked(conn, option_status)
            end
        end
      end
      
      receive do
        {^producer, :meta, _meta} -> #discard
      end

      conn
      |> set_response_headers.(producer)
      |> set_response_status.(producer)
      |> response_chunked(producer)
    end
  end

  def response(producers, conn, options) when is_list(producers) do
    if (Dict.get(options, :compress, false)) do
      response_compressed(producers, conn, options)
    else
      Enum.each(producers, fn(producer) ->
        send(producer, { self, :ready })
      end)
      
      option_status = Dict.get(options, :status, 200)
      option_headers = Dict.get(options, :headers, %{})

      if (conn.state == :chunked) do
        response_chunked_multi(conn, producers)
      else
        conn
        |> set_headers(option_headers)
        |> send_chunked(option_status)
        |> response_chunked_multi(producers)
      end
    end
  end
  
  @doc """
  `concatenate_json` takes a list of producers (Elixir  PIDs), 
  reads their messages and returns a new producer. The new producer´s
  message (body) is formatted as a JSON list where each item corresponds to a
  response converted to a JSON map.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by CrocodilePear).
    * `options` - Options (see below). Default: [].
    
  Options:
    * `:body_only` - boolean indicating whether only the body (payload) of an
    response should be included in the response---otherwise headers, status and
    meta is also included.
  """
  @spec concatenate_json(producers, Dict.t) :: [pid]
  def concatenate_json(producers, options \\ []) when is_list(producers) do
    {:ok, new_producer} = Task.start_link(fn ->
      outer_self = self

      Enum.each(producers, fn(producer) ->
        Task.start_link(fn ->
          json =
            if (Dict.get(options, :body_only, false)) do
              %{body: body} = collect_response(producer)

              case Poison.decode(body) do
                {:ok, body_decoded} -> 
                  Poison.encode!(body_decoded)

                _not_json -> 
                  Poison.encode!(body)
              end
            else
              %{body: body} = response = collect_response(producer)

              case Poison.decode(body) do
                {:ok, body_decoded} ->
                  Dict.put(response, :body, body_decoded)
                  |> Poison.encode!

                _not_json -> 
                  Poison.encode!(response)
              end
            end

          send(outer_self, { :json, json })
        end)
      end)

      consumer = receive do
        { pid, :ready } -> pid
      end

      send(consumer, { self, :meta, %{} })
      send(consumer, { self, :status, 200 })
      send(consumer, { self, :headers, %{"Content-Type" => "application/json"} })

      if (Enum.empty?(producers)) do
        send(consumer, { self, :chunk, "[]"})
      else
        [_head | rest] = producers

        if (Enum.empty?(rest)) do
          receive do
            { :json, json } -> send(consumer, { self, :chunk, "[" <> json <> "]" })
          end
        else
          receive do
            { :json, json } -> send(consumer, { self, :chunk, "[" <> json })
          end

          [_head | count] = rest

          Enum.each(count, fn(_) ->
            receive do
              { :json, json } -> send(consumer, { self, :chunk, "," <> json })
            end
          end)

          receive do
            { :json, json } -> send(consumer, { self, :chunk, "," <> json <> "]" })
          end
        end
      end

      send(consumer, { self, :done })
    end)

    [new_producer]
  end
  
  @doc """
  `collect_response` works as a way to break out of the asynchronous nature of
  the pipeline. `collect_response` takes a list of producers and returns a (list
  of) Dict containing the body (payload), headers, status code and meta data.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by CrocodilePear).
  """
  @spec collect_response(producers) :: [response] | response
  
  def collect_response(producers) when is_list(producers) do
    Enum.map(producers, &collect_response/1)
  end

  def collect_response(producer) when is_pid(producer) do
    send(producer, { self, :ready })
    aggregate_response(producer)
  end

  @doc """
  `transform` can asynchronously transform responses within the pipeline. The
  function takes a lambda function as its second argument. The lambda function
  must take a Dict and return an updated Dict. The Dict must have the following
  keys: `:status` (integer), `:headers` (map), `:body` (string) and `:meta` 
  (map).
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by CrocodilePear).
    * `fun` - Lambda function or list of lambda functions. If the argument is
    one function, it will be applied to all messages---if the argument is a
    list of functions, one function will be applied to one response by zipping
    them together and the list must therefore be of the same length as the 
    producers.
  """
  @spec transform(producers, fun | [fun]) :: producers
  def transform(producers, func) when is_list(producers) and is_function(func) do
    transform(producers, List.duplicate(func, length(producers)))
  end

  def transform(producers, func) when is_list(producers) and is_list(func) do
    Enum.zip(producers, func) |> Enum.map(fn({producer, func}) ->
      {:ok, new_producer} = Task.start_link(fn ->
                
        %{status: status, headers: headers, body: body, meta: meta} = func.(collect_response(producer))

        consumer = receive do
          { pid, :ready } -> pid
        end

        send(consumer, { self, :meta, meta })
        send(consumer, { self, :status, status })
        send(consumer, { self, :headers, headers })
        send(consumer, { self, :chunk, body })
        send(consumer, { self, :done })
      end)

      new_producer
    end)
  end
  
  @doc """
  `timer` is used to log what happens within the pipeline in order to benchmark.
  It will ouput the timestamp when the timer-function is invoked. If the 
  argument is producers, then each individual message will be logged with
  timestamps. The default Elixir Logger is used.
  
  Args:
    * `thing` - can be any kind of structure, if it is a producer, then each
    individual message passed will be logged.
    * `label` - optional label (string) which will be attached to all log 
    messages.
  """
  @spec timer(term, String.t) :: term
  def timer(thing, label \\ "")
  
  def timer(producers, label) when is_list(producers) do
    if !(producers |> Enum.map(&(!is_pid(&1))) |> Enum.any?) do
      Enum.map(producers, fn(producer) -> 
        
        {:ok, new_producer} = Task.start_link(fn ->
          consumer = receive do
            { pid, :ready } -> pid
          end
          
          resend(consumer)
        end)
        
        Task.start_link(fn ->
          send(producer, { self, :ready })
          timer_messages(producer, new_producer, label)
        end)
        
        new_producer
      end)
    else
      case label do
        "" -> Logger.info(inspect(:os.timestamp))
        _ -> Logger.info("#{inspect(:os.timestamp)} (#{label})")
      end
      
      producers
    end
  end

  def timer(thing, label) do
    case label do
      "" -> Logger.info(inspect(:os.timestamp))
      _ -> Logger.info("#{inspect(:os.timestamp)} (#{label})")
    end

    thing
  end

  ## Helpers
  
  @spec response_compressed(producers, Conn.t, Dict.t) :: Conn.t
  defp response_compressed(producer, conn, options) when is_pid(producer) do
    %{body: body, headers: headers, status: status} = collect_response(producer)
    
    option_headers = Dict.get(options, :headers, [])
    option_status = Dict.get(options, :status, status)
    
    chunk_status = 
      conn
      |> set_headers(Dict.merge(headers, option_headers))
      |> put_resp_header("content-encoding", "gzip")
      |> send_chunked(option_status)
      |> chunk(:zlib.gzip(body))
      
    case chunk_status do
      {:ok, new_conn} -> new_conn

      {:error, reason} ->
        Logger.error("Unable to chunk response: #{reason}")
        conn
    end
  end
  
  defp response_compressed(producers, conn, options) when is_list(producers) do
    body = 
      producers
      |> collect_response
      |> Enum.map(&(Dict.get(&1, :body)))
      |> Enum.join
      |> :zlib.gzip
    
    option_headers = Dict.get(options, :headers, [])
    option_status = Dict.get(options, :status, 200)
    
    chunk_status =
      if (conn.state == :chunked) do
        chunk(conn, body)
      else
        conn
        |> set_headers(option_headers)
        |> put_resp_header("content-encoding", "gzip")
        |> send_chunked(option_status)
        |> chunk(body)
      end
    
    case chunk_status do
      {:ok, new_conn} -> new_conn

      {:error, reason} ->
        Logger.error("Unable to chunk response: #{reason}")
        conn
    end
  end
  
  @spec resend(pid) :: :ok
  defp resend(consumer) do
    receive do
      {_producer, atom, msg} ->
        send(consumer, { self, atom, msg })
        resend(consumer)
      
      {_producer, :done} ->
        send(consumer, { self, :done })
    end
    
    :ok
  end
  
  @spec timer_messages(pid, pid, String.t) :: :ok
  defp timer_messages(producer, new_producer, label) do
    log_msg = fn(atom, label) ->
      case label do
        "" -> Logger.info("#{inspect(:os.timestamp)} [#{atom}] on #{inspect(self)}")
        _label -> Logger.info("#{inspect(:os.timestamp)} [#{atom}] (#{label}) on #{inspect(self)}")
      end
    end
    
    receive do
      {^producer, atom, msg} -> 
        log_msg.(atom, label)
        send(new_producer, { self, atom, msg })
        timer_messages(producer, new_producer, label)
      
      {^producer, :done} ->
        log_msg.(:done, label)
        send(new_producer, { self, :done })
    end
    
    :ok
  end


  @spec response_chunked_multi(Conn.t, [pid]) :: Conn.t
  defp response_chunked_multi(conn, []), do: conn

  defp response_chunked_multi(conn, producers) do
    producer = receive do
      {producer, :headers, _headers} -> producer
    end
    
    receive do
      {^producer, :meta, _meta} -> #discard
    end

    conn = receive do
      {^producer, :status, _status} -> response_chunked(conn, producer)
    end

    response_chunked_multi(conn, List.delete(producers, producer))
  end

  @spec get_hackney_chunk(reference, pid) :: :ok
  defp get_hackney_chunk(id, consumer) do
    receive do
      {:hackney_response, ^id, {:error, reason}} ->
        throw reason

      {:hackney_response, ^id, :done} ->
        send(consumer, { self, :done })
        
      {:hackney_response, ^id, chunk} ->
        send(consumer, { self, :chunk, chunk })
        get_hackney_chunk(id, consumer)
    end
    
    :ok
  end

  @spec response_chunked(Conn.t, pid) :: Conn.t
  defp response_chunked(conn, producer) do
    receive do
      {^producer, :chunk, chunk} ->
        case chunk(conn, chunk) do
          {:ok, new_conn} -> 
            response_chunked(new_conn, producer)
          
          {:error, reason} -> 
            Logger.error("Unable to chunk response: #{reason}")
            conn
        end

      {^producer, :done} ->
        conn
    end
  end

  @spec set_headers(Conn.t, Dict.t) :: Conn.t
  defp set_headers(conn, headers) do
    Enum.reduce(headers, conn, fn({key, value}, conn) ->
      put_resp_header(conn, key, value)
    end)
  end

  @spec aggregate_response(pid, Dict.t) :: response
  defp aggregate_response(producer, response \\ %{}) do
    receive do
      {^producer, :chunk, chunk} ->
        response = Dict.update(response, :body, chunk, fn(existing) -> existing <> chunk end)
        aggregate_response(producer, response)
        
      {^producer, key, value} ->
        response = Dict.put_new(response, key, value)
        aggregate_response(producer, response)

      {^producer, :done} ->
        response
    end
  end
end
