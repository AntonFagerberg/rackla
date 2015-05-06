defmodule Rackla do
  @moduledoc """
  Rackla is an open source framework for building API gateways. When we say API gateway, we mean to proxy and potentially enhance the communication between servers and HTTP clients, such as browsers, by transforming the data. The communication can be enhanced by throwing away unnecessary data, concatenating multiple requests or convert the data between different formats. 

  With Rackla you can execute multiple HTTP-requests and transform them in any way you want - asynchronous end to end. The technology used inside Rackla is based on a list of Elixir processes (actors) which follows a defined communication protocol. By piping functions together and forming a pipeline, these processes can communicate independently (asynchronously) of each other to achieve a high level of performance. 

  The protocol used between the Elixir processes is by default abstracted away from the framework user. By instead utilizing helper functions, the developer can gain the performance benefits but without having to deal with any message passing. (There is however nothing stopping the developer who want to tap directly in to the process messaging.)

  Rackla utilizes [Plug](https://github.com/elixir-lang/plug) to expose new end-points and communicate with clients over HTTP. Internally, it uses [Hackney](https://github.com/benoitc/hackney) to make HTTP requests and [Poison](https://github.com/devinus/poison) for dealing with JSON.

  ## Minimal installation (as Mix dependency)

  You can add Rackla to your existing application by using the following Mix dependency:

      defp deps do
        [
          {:rackla, "~> 1.0"} # TODO Fix correct
        ]
      end

  However, this setup is much more complicated and it is recommended that you do a "full installation" for your projects (described below).

  ## Full installation (clone example project)

  You can clone [this GitHub repository](https://github.com/AntonFagerberg/rackla) in order to get a complete working setup with runnable example end-points and tests. The cloned project includes all infrastructure needed to easily expose (run) your end-points or deploy your API gateway to a cloud service such as Heroku. 

  ### Starting the application
  The application will be started automatically when running `iex -S mix`. You can also start it by running `mix server`. By default, it will start on port 4000, but it can be changed either from the file `config/config.exs` or by creating an environment variable named PORT.

  You can also create an escript with `mix escript.build` and then run the file `rackla`.

  ### Deploy to Heroku
  The [Heroku Buildpack for Elixir](https://github.com/HashNuke/heroku-buildpack-elixir) works out of the box for Rackla when doing a full installation.

  ## Structs
  ### Rackla.Request
   * `:url` - Address to call.
   * `:method` - HTTP verb, defaults to `:get`.
   * `:body` - The request payload, defaults to empty string.
   * `:headers` - Request headers (map), defaults to empty map.
   * `:options` - Request specfic ptions such as timeout limits (overwrites the global one if provided), default to empty map.
   * `:meta` - Meta map which can contain any arbitrary used defined data, defaults to empty map.
   
  ### Rackla.Response
  * `:status` - HTTP response status (such as 200 for OK).
  * `:headers` - Map of response headers.
  * `:body` - Binary response body.
  * `:meta` - The meta map used inside Rackla with arbitrary data.
  * `:error` - Error - either an atom or a thrown exception. If `:error` is not `nil`, the rest of the response should be considered invalid.

  ## Examples

  ### Simple request/response
  A simple proxy can be created by exposing the endpoint `/proxy`. Here we get the target url from the query string, example: `/proxy?www.example.com`. We can then create a simple pipeline by starting with the query string, piping it to the request function which will make a GET request to the URL and finally piping the result to the response function. The response function will then take the `conn` struct from Plug and respond to the client.

      get "/proxy" do
        conn.query_string
        |> request
        |> response
      end

  ### Multiple requests
  In the same manner as the previous example, we can use the query-string to retrieve any number of request URLs. In this example, we take a list of URLs from the query string separated by the `|` character, for example: `/proxy/multi?www.example1.com|www.example2.com`.

      get "/proxy/multi" do
        String.split(conn.query_string, "|")
        |> request
        |> response
      end

  In this example, all requests are executed asynchronously - the first responding request will be sent first to the client. The response is therefore nondeterministic and the response body is just each individual response's payload concatenated to in to one. This is in most cases useless so let's continue and see what we can do to improve that.

  ### Concatenate JSON
  The function `concatenate_json` is one approach to solve the problem from the previous example. When we get responses, especially out of order, we probably want to know which response belongs which request. Concatenate JSON will give us this and many more benefits. When piping to `concatenate_json`, all responses will be turned in to a JSON-list where each request has its own JSON-object containing the status-code, headers, body and a meta-field which developers can use to add additional information.

      get "/proxy/multi/concat-json" do
        String.split(conn.query_string, "|")
        |> request
        |> concatenate_json
        |> response
      end
      
  The order in the JSON list is guaranteed to follow the same as the order in as the list of producers.

  If you're only interested in the body (payload) of the response, you can pass `body_only: true` to the `concatenate_json` function which will then discard all other data. Every item in the JSON-list is then just the body from the response.

  ### Transform
  The function `transform` is an abstraction which makes it easy to manipulate the responses asynchronously. Transform takes a single lambda-function as its only argument. The lambda-function in turn should take a `Rackla.Response` struct and must return a new `Rackla.Response` struct. As an example, we can look at the identity function (which does nothing):

      get "/proxy/transform/identity" do
        identity = fn(response) ->
          if (is_nil(response.error)) do
            response
            |> Map.update!(:status, fn(x) -> x end)
            |> Map.update!(:headers, fn(x) -> x end)
            |> Map.update!(:body, fn(x) -> x end)
            |> Map.update!(:meta, fn(x) -> x end)
          else
            response # Handle error in some way
          end
        end

        request(conn.query_string)
        |> transform(identity)
        |> response
      end

  The transform function works on a "per response" basis.

  ### Collect response
  Sometimes you want to break out of the asynchronous behavior. In such cases, you can utilize the `collect_response` function. When `collect_response` is used, it will wait until all request has responded and collect all responses in a list. Each item in the list is a `Rackla.Response` struct.

  ### Multiple pipelines
  It is important to point out that you can define multiple pipelines - either to be used in parallel or recursively. You may have two different collections of URLs which should be processed in different ways. This can be accomplished by creating two pipelines which are then concatenated:

      get "/multi/pipeline" do
        pipeline_1 = list_of_URLs_1 |> request |> transform(do_things_1)
        pipeline_2 = list_of_URLs_2 |> request |> transform(do_things_2)
        
        pipeline_1 ++ pipeline_2
        |> concatenate_json
        |> response
      end

  Using multiple pipelines in this fashion will process all requests asynchronously and respond in the same manner.

  In a similar way, you can create recursive pipelines. This is a good idea in cases where you want to extend a response with data from another request. The easiest way to do this is to start a new pipeline inside the lambda function used in the `transform` function. Just remember that the lambda function used in `transform` must return a `Rackla.Response` struct so it is a good idea to use `collect_response` here to convert the internal pipeline to a `Rackla.Response` struct in the end. Since the `transform` function is executed asynchronously, the outer pipeline will not be affected when using the blocking `collect_response` in a pipeline inside a `transform` function.

      get "/recursive/pipeline" do
        some_function = fn(response) ->
          urls_from_respone = get_some_things(response)
          
          urls_from_response
          |> request
          |> collect_response
        end
        
        url_list
        |> request
        |> transform(some_function)
        |> response
      end

  ### Advanced requests
  The function `request` can either take strings (URLs) which will be turned in to GET requests - or you can specify a `Rackla.Request` struct with more advanced details (see code documentation for more information about all options).
   
  Note that the `request` function accepts any of the following data-types as its parameter:

  * String (single URL)
  * List of strings (multiple URLs)
  * `Rackla.Request` struct (single request)
  * List of `Rackla.Request` stucts (multiple requests)

  It is also possible to pass `Rackla.Response` structs to the `request` function. When this is done, the response will be directly retransmitted to the consumers as any other request (the request will not be resent to the back-end). One reason for allowing this is behavior is to be able to compose a completed pipeline with a brand new one.

  ### Timers
  Timers can be used anywhere in the pipeline to log timestamps. The timers can be used between both synchronous and asynchronous functions to determine what happens on which moments in time. On asynchronous calls which follows the protocol defined by Rackla, a log event will be triggered on every message between the Elixir processes.

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
      |> response
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

      response(compress: true)

  ### Decompression
  When executing requests to a server which replies with compressed data, you have to decompress it yourself before processing it (unless you want to send it directly to the client). If the server uses GZip-compression, then you can use the Zlib module in Erlang to decompress the body, for example by creating a `transform` lambda-function:

      transform(fn(response) -> Map.update!(response, :body, &:zlib.gunzip/1) end)

  ### Working with JSON
  Rackla uses [Poison](https://github.com/devinus/poison) for working with JSON internally. It is a great library which converts JSON-structures to Elixir-structures and vice versa. Poison can of course also be used in the end-points for transforming and manipulating JSON data in the pipeline.

  ### Working with XML (and other formats)
  There is currently no special XML support (or any other format except JSON). You can request data in any format over HTTP, process it with any third-party library and respond with it - but there are no built in helper functions such as the `concatenate_json` used for JSON.

  ### Caching
  Rackla has no built in support for caching but you can, for example, use [EchoTeams Erlang memcached client library](https://github.com/EchoTeam/mcd) which we've successfully experimented with.

  ### Cross-Origin Resource Sharing (CORS) 
  In order to use CORS in your API gateway, you can use any tool which works with Plug such as [cors_plug](https://github.com/mschae/cors_plug).

  ## Error handling

  Internally, the messages passed between Elixir processes are:
   * `:status` - 1 message
   * `:headers` - 1 message
   * `:meta` - 1 message
   * `:body` - N messages
   * `:done` - 1 message
   
  However, errors can occur at any point of time between the transmission of these messages. If an error occurs, an `:error` message will be sent. It is guaranteed that no further message will be sent from a producer after an `:error` message has been sent. 
   
  The reason for sending an `:error` message can be everything from a non-responding back-end server or invalid DNS lookups to invalid code in a `transform` function. Rackla will never raise any exceptions and even the code which the framework user provides inside the `transform` lambda function will be caught and sent as an `:error` message automatically.

  This means that the framework user can handle the errors either directly inside a `transform` lambda function or propagate them to the client. The function `concatenate_json` will, unless `body_only: true`, include the error message to the client.

  ### Logger
  The `:error` message will also be sent to the Logger when it is produced or discovered. There are three variations of how this is handled.
   * An `info` level message will be sent on errors which the user is expected to fix (if he/she wants to). These errors are related to the request such as DNS failures, timeouts etc.
   * An `warn` level message will be sent on errors which can't be fixed. These errors occurs when parts of the data has been sent to the client already or if the connection is lost in the middle of transmission.
   * An `warn` level message will be sent if an `:error` message is silently discarded such as when `concatenate_json(body_only: true)` is invoked.

  ### Example (error propagation)

      get "/proxy/invalid-transform" do
        invalid_transform = fn(response) ->
          Dict.get!(response, :nope)
        end
        
        conn.query_string
        |> request
        |> transform(invalid_transform)
        |> concatenate_json
        |> response
      end

  Here we have defined an end-point which will proxy a URL and concatenate the response as JSON. We have defined a lambda function `invalid_transform` which will try to get the non-existing key `:nope`. This exception will be caught by Rackla and it will be propagated down to the client:

      [
         {
            "status":null,
            "meta":{

            },
            "headers":{

            },
            "error":{
               "self":false,
               "module":"Elixir.Dict",
               "function":"get!",
               "arity":2,
               "__exception__":true
            },
            "body":""
         }
      ]

  ### Router errors
  Note that errors regarding the routing and `Plug` have to be dealt with outside Rackla. One approach is to check out the [Plug.ErrorHandler](http://hexdocs.pm/plug/Plug.ErrorHandler.html).

  ## Learn more
  For more information, you can see some test end-points defined in [lib/router.ex](https://github.com/AntonFagerberg/rackla/blob/master/lib/router.ex). The file [lib/rackla/rackla.ex](https://github.com/AntonFagerberg/rackla/blob/master/lib/rackla/rackla.ex)  contains documentation for all functions - the documentation is also available online (TODO!).
  """
  
  import Plug.Conn
  require Logger
  
  @type requests  :: String.t | Rackla.Request.t | [String.t] | [Rackla.Request.t]
  @type producers :: pid | [pid]

  @doc """
  `request` is usually the beginning of a pipeline. It executes all
  HTTP requests concurrently and returns a list of Elixir PIDs (producers) which
  will respond as soon as a response is available.
  
  Args:
    * `requests` - String (URL), `Rackla.Request` struct or list of strings or 
    `Rackla.Request` structs.
    * `options` - (Optional) Dict with additional options (see below). Note that these will 
    be overwritten if a request has conflicting options in itself.
    
  Options:
    * `:insecure` - Boolean whether to perform SSL connections without checking
    the certificate. Default: false.
    * `:connect_timeout` - Timeout used when estabilishing a connection, in 
    milliseconds. Default: 5_000.
    * `:receive_timeout` - Timeout used when receiving a connection, in 
    milliseconds. Default: 5_000.
  """
  @spec request(requests, Dict.t) :: [pid]
  def request(requests, options \\ %{})
  
  def request(request, options) when is_bitstring(request) or is_map(request) do
    request([request], options)
  end

  def request(requests, options) when is_list(requests) do
    Enum.map(requests, fn(request) ->
      if is_binary(request), do: request = %Rackla.Request{url: request}
      
      {:ok, producer} = 
        case request do
          %Rackla.Request{
            method: method,
            url: url,
            headers: headers,
            body: body,
            options: request_options,
            meta: meta
          } ->
            Task.start_link(fn ->
              options = Map.merge(request_options, options)
              
              case :hackney.request(
                method,
                url,
                headers |> Enum.into([]),
                body,
                [
                  insecure: Map.get(options, :insecure, false),
                  connect_timeout: Map.get(options, :connect_timeout, 5_000),
                  recv_timeout: Map.get(options, :receive_timeout, 5_000),
                  async: true,
                  stream_to: self
                ]
              ) do
                {:ok, id} ->
                  consumer = receive do
                    { pid, :ready } -> pid
                  end
                  
                  send(consumer, { self, :meta, meta })

                  receive do
                    {:hackney_response, ^id, {:headers, headers}} ->
                      send(consumer, { self, :headers, Enum.into(headers, %{}) })
                      
                    {:hackney_response, ^id, {:error, reason}} ->
                      send(consumer, { self, :error, reason })
                      Logger.info("HTTP request error: #{inspect(reason)}")
                      Kernel.exit(:normal)
                  end

                  receive do
                    {:hackney_response, ^id, {:status, code, _reason}} -> 
                      send(consumer, { self, :status, code })
                      
                    {:hackney_response, ^id, {:error, reason}} ->
                      send(consumer, { self, :error, reason})
                      Logger.info("HTTP request error: #{inspect(reason)}")
                      Kernel.exit(:normal)
                  end

                  get_hackney_chunk(id, consumer)
                  
                {:error, reason} ->
                  Logger.info("HTTP request error: #{inspect(reason)}")
                  
                  consumer = receive do
                    { pid, :ready } -> pid
                  end
                  
                  send(consumer, { self, :error, reason })
              end
            end)
            
          %Rackla.Response{
            status: status,
            headers: headers,
            body: body,
            meta: meta,
            error: error
          } ->
            Task.start_link(fn ->
              consumer = receive do
                { pid, :ready } -> pid
              end
              
              if (is_nil(error)) do
                send(consumer, { self, :status, status })
                send(consumer, { self, :meta, meta })
                send(consumer, { self, :headers, headers })
                send(consumer, { self, :chunk, body })
                send(consumer, { self, :done })
              else
                send(consumer, { self, :error, error })
              end
            end)
        end

      producer
    end)
  end
  
  @doc """
  `response` uses `conn` from Plug in order to transmit the responses from the 
  producers to the client over HTTP. 
  
  `response` is a macro which works just like `response_conn`. The only 
  difference between them is that `response` picks up `conn` implicitly from the
  scope while `conn` has to be passed as a parameter to `response_conn`.
  
  If there is only one item in the `producers` list, that `producer`'s headers
  and status code will be added to the response per default if not already sent.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by Rackla).
    * `options` - (Optional) Options (see below).
    
  Options:
    * `:compress` - boolean whether to gzip response or note. Default: false.
    * `:headers` - response headers (map). Default: %{}.
    * `:status` - HTTP response status code. Default: 200 (OK)
  """
  defmacro response(producers, options \\ []) do
    quote do
      response_conn(unquote(producers), var!(conn), unquote(options))
    end
  end

  @doc """
  `response_conn` uses `conn` from Plug in order to transmit the responses from the 
  producers to the client over HTTP.
  
  If there is only one item in the `producers` list, that `producer`'s headers
  and status code will be added to the response per default if not already sent.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by Rackla).
    * `conn` - Plug´s `conn` structure.
    * `options` - (Optional) Options (see below).
    
  Options:
    * `:compress` - boolean whether to gzip response or note. Default: false.
    * `:headers` - response headers (map). Default: %{}.
    * `:status` - HTTP response status code. Default: 200 (OK)
  """
  @spec response_conn(producers, Conn.t, Dict.t) :: Conn.t
  def response_conn(producers, conn, options \\ [])

  def response_conn([producer], conn, options) do
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
            
          {^producer, :error, reason} ->
            Logger.info("Error message received during response: #{inspect(reason)}")
            conn
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
            
          {^producer, :error, reason} ->
            Logger.info("Error message received during response: #{inspect(reason)}")
            conn
        end
      end
      
      receive do
        {^producer, :meta, _meta} -> 
          :ok
          
        {^producer, :error, reason} ->
          Logger.info("Error message received during response: #{inspect(reason)}")
          conn
      end

      conn
      |> set_response_headers.(producer)
      |> set_response_status.(producer)
      |> response_chunked(producer)
    end
  end

  def response_conn(producers, conn, options) when is_list(producers) do
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
  
  The order in the JSON list is guaranteed to follow the same as the order in 
  as the list of producers.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by Rackla).
    * `options` - (Optional) Options (see below).
    
  Options:
    * `:body_only` - boolean indicating whether only the body (payload) of an
    response should be included in the response - otherwise headers, status and
    meta is also included.
  """
  @spec concatenate_json(producers, Dict.t) :: [pid]
  def concatenate_json(producers, options \\ []) when is_list(producers) do
    {:ok, new_producer} = Task.start_link(fn ->
      producer_count = length(producers)
      
      consumer = receive do
        { pid, :ready } -> pid
      end

      send(consumer, { self, :meta, %{} })
      send(consumer, { self, :status, 200 })
      send(consumer, { self, :headers, %{"Content-Type" => "application/json"} })
      
      producers
      |> Enum.map(&(Task.async(fn -> collect_response(&1) end)))
      |> Enum.with_index
      |> Enum.each(fn({task, index}) ->
        json =
          if (Dict.get(options, :body_only, false)) do
            %Rackla.Response{body: body} = Task.await(task)

            case Poison.decode(body) do
              {:ok, body_decoded} -> 
                Poison.encode!(body_decoded)

              _not_json -> 
                Poison.encode!(body)
            end
          else
            %Rackla.Response{body: body, error: error} = response = Task.await(task)
            
            if (!is_nil(error)), do: Logger.warn("Discarding error in concatenate_json: #{inspect(error)}")

            case Poison.decode(body) do
              {:ok, body_decoded} ->
                Map.put(response, :body, body_decoded)
                |> Poison.encode!

              _not_json -> 
                Poison.encode!(response)
            end
          end
          if (index == 0) do
            json = "[#{json}"
          else
            json = ",#{json}"
          end
          
          if (producer_count == index + 1), do: json = "#{json}]"
          
          send(consumer, { self, :chunk, json })
      end)
      
      send(consumer, { self, :done })
    end)

    [new_producer]
  end
  
  @doc """
  `collect_response` works as a way to break out of the asynchronous nature of
  the pipeline. `collect_response` takes a list of producers and returns a (list
  of) `Rackla.Response` struct containing the body (payload), headers, status 
  code, potential errors and meta data.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by Rackla).
  """
  @spec collect_response(producers) :: [Rackla.Response.t] | Rackla.Response.t
  
  def collect_response(producers) when is_list(producers) do
    producers
    |> Enum.map(&(Task.async(fn -> collect_response(&1) end)))
    |> Enum.map(&Task.await/1)
  end

  def collect_response(producer) when is_pid(producer) do
    send(producer, { self, :ready })
    aggregate_response(producer)
  end

  @doc """
  `transform` can asynchronously transform responses within the pipeline. The
  function takes a lambda function as its only argument. The lambda function
  must take a `Rackla.Response` and return an `Rackla.Response`.
  
  Args:
    * `producers` - List of producers (Elixir PIDs which follows the protocol
    defined by Rackla).
    * `fun` - Lambda function or list of lambda functions. If the argument is
    one function, it will be applied to all messages - if the argument is a
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
                
        try do
          %Rackla.Response{
            status: status,
            headers: headers,
            body: body,
            meta: meta,
            error: error
          } = func.(collect_response(producer))

          consumer = receive do
            { pid, :ready } -> pid
          end

          send(consumer, { self, :meta, meta })
          send(consumer, { self, :status, status })
          send(consumer, { self, :headers, headers })
          send(consumer, { self, :chunk, body })
          send(consumer, { self, :done })
        rescue
          exception -> 
            consumer = receive do
              { pid, :ready } -> pid
            end
            
            send(consumer, { self, :error, exception })
        end
      end)

      new_producer
    end)
  end
  
  @doc """
  `timer` is used to log what happens within the pipeline in order to benchmark.
  It will ouput the timestamp when the `timer` function is invoked. If the 
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
        Logger.error("Unable to chunk response: #{inspect(reason)}")
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
        Logger.error("Unable to chunk response: #{inspect(reason)}")
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
    {producer, conn} = 
      receive do
        {producer, :headers, _headers} -> 
          receive do
            {^producer, :meta, _meta} -> 
              receive do
                {^producer, :status, _status} -> 
                  {producer, response_chunked(conn, producer)}
                  
                {^producer, :error, reason} ->
                  Logger.warn("Error message received during response: #{inspect(reason)}")
                  {producer, conn}
              end

            {^producer, :error, reason} ->
              Logger.warn("Error message received during response: #{inspect(reason)}")
              {producer, conn}
          end
        
        {producer, :error, reason} ->
          Logger.warn("Error message received during response: #{inspect(reason)}")
          {producer, conn}
      end
    
    response_chunked_multi(conn, List.delete(producers, producer))
  end

  @spec get_hackney_chunk(reference, pid) :: :ok
  defp get_hackney_chunk(id, consumer) do
    receive do
      {:hackney_response, ^id, {:error, reason}} ->
        send(consumer, { self, :error, reason})
        Logger.info("HTTP request error: #{inspect(reason)}")
        Kernel.exit(:normal)

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
      {^producer, :error, reason} ->
        Logger.warn("Error message received during response: #{inspect(reason)}")
        conn
        
      {^producer, :chunk, chunk} ->
        case chunk(conn, chunk) do
          {:ok, new_conn} -> 
            response_chunked(new_conn, producer)
          
          {:error, reason} -> 
            Logger.error("Unable to chunk response: #{inspect(reason)}")
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

  @spec aggregate_response(pid, Rackla.Response.t) :: Rackla.Response.t
  defp aggregate_response(producer, response \\ %Rackla.Response{}) do
    receive do
      {^producer, :chunk, chunk} ->
        response = Map.update(response, :body, chunk, fn(existing) -> existing <> chunk end)
        aggregate_response(producer, response)

      {^producer, :error, reason} ->
        Map.put(response, :error, reason)
        
      {^producer, key, value} ->
        response = Map.put(response, key, value)
        aggregate_response(producer, response)

      {^producer, :done} ->
        response
    end
  end
end
