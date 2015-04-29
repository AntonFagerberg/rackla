Rackla
=============

Rackla is an open source framework for building API gateways. When we say API gateway, we mean to proxy and potentially enhance the communication between servers and HTTP clients, such as browsers, by transforming the data. The communication can be enhanced by throwing away unnecessary data, concatenate multiple requests or convert the data between different formats. 

With Rackla you can execute multiple HTTP-requests and transform them in any way you want - asynchronous end to end. The technology used inside Rackla is based on a list of Elixir processes (actors) which follows a defined communication protocol. By piping functions together and forming a pipeline, these processes can communicate independently (asynchronously) of each other to achieve a high level of performance. 

The protocol used between the Elixir processes is by default abstracted away from the framework user. By instead utilizing helper functions, the developer can still gain the performance benefits but without having to deal with any message passing. There is however nothing stopping the developer who want to tap directly in to the process messaging.

Rackla utilizes [Plug](https://github.com/elixir-lang/plug) to expose new end-points and communicate with clients over HTTP. Internally, it uses [Hackney](https://github.com/benoitc/hackney) to make HTTP requests and [Poison](https://github.com/devinus/poison) for dealing with JSON.

## Minimal installation (as Mix dependency)

You can add Rackla to your existing application by using the following Mix dependency:

```elixir
defp deps do
  [
    {:rackla, "~> 1.0"} # TODO Fix correct
  ]
end
```

However, this setup is more complicated and it is recommended that you do a "full installation", described below, for your projects.

## Full installation (clone example project)

You can clone [this GitHub repository](https://github.com/AntonFagerberg/rackla) in order to get a complete working setup with runnable example end-points and tests. This includes all infrastructure needed to easily expose (run) your end-points or deploy your API gateway to a service such as Heroku. 

### Starting the application
The application will be started automatically when running `iex -S mix`. You can also start it by running `mix server`. By default, it will start on port 4000, but it can be changed either from the file `config/config.exs` or by creating an environment variable named PORT.

You can also create an escript with `mix escript.build` and then run the file `rackla`.

### Deploy to Heroku
The [Heroku Buildpack for Elixir](https://github.com/HashNuke/heroku-buildpack-elixir) works out of the box for Rackla when doing a full installation.

## Examples

### Simple request/response
A simple proxy can be created by exposing the endpoint `/proxy` where we get the target url from the query string, example: `/proxy?www.example.com`. We can then create a simple pipeline by starting with the query-string, piping it to the request function which will make a GET request to the URL from the query-string and finally piping the result to the response function. The response function will then take the `conn`-struct from Plug and respond to the client.

```elixir
get "/proxy" do
  conn.query_string
  |> request
  |> response(conn)
end
```

### Multiple requests
In the same manner as the previous example, we can use the query-string to retrieve any number of request URLs. In this example, we take a list of URLs from the query string separated by the `|` character, for example: `/proxy/multi?www.example1.com|www.example2.com`.

```elixir
get "/proxy/multi" do
  String.split(conn.query_string, "|")
  |> request
  |> response(conn)
end
```

In this example, all requests are executed asynchronously and so the first request which is responding will be sent first to the client. The response is therefore nondeterministic and the response body is just each individual response concatenated to one response. This is in most cases useless so let's continue and see what we can do to improve that.

### Concatenate JSON
The function `concatenate_json` solves the problem from the previous example. When we get responses, especially out of order, we probably want to know which response belongs which request. Concatenate JSON will give us this and many more benefits. When piping to `concatenate_json`, all responses will be turned in to a JSON-list where each request has its own JSON-object containing the status-code, headers, body and a meta-field which developers can use to add additional information. By default, the meta-field will contain the requested URL so that all items easily can be identified.

```elixir
get "/proxy/multi/concat-json" do
  String.split(conn.query_string, "|")
  |> request
  |> concatenate_json
  |> response(conn)
end
```

If you're only interested in the body of the response, you can pass `body_only: true` to the `concatenate_json` function which will then discard all other data. Every item in the JSON-list is then just the body from the response.

### Transform
The function `transform` is an abstraction which makes it easy to manipulate the responses asynchronously. Transform takes a single lambda-function as its only argument. The lambda-function in turn should take a response-map and must return a new response-map with the same keys. The response-map has four keys which can be accessed: `:meta`, `:status`, `:headers` and `:body`. As an example, we can look at the identity function (which does nothing):

```elixir
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
```

The transform function works on a "per response" basis, on any number of requests, and is fully asynchronous.

### Collect response
Sometimes you want to break out of the asynchronous behavior. In such cases, you can utilize the `collect_response` function. When `collect_response` is used, it will wait until all request has responded and collect all responses in a list. Each item in the list is a response-map with the keys `:status`, `:headers`, `:body` and `:meta` and the list will be sorted in the same way as the requests were executed.


### Multiple pipelines
It is important to point out that you can define multiple pipelines - either to be used in parallel or recursively. You may have two different collections of URLs which should be processed in different ways. This can be accomplished by creating two pipelines which are then concatenated:

```elixir
get "/multi/pipeline" do
  pipeline_1 = list_of_URLs_1 |> request |> transform(do_things_1)
  pipeline_2 = list_of_URLs_2 |> request |> transform(do_things_2)
  
  pipeline_1 ++ pipeline_2
  |> concatenate_json
  |> response(conn)
end
```

Using multiple pipelines in this fashion will process all requests asynchronously and respond in the same manner.

In the same way, you can create recursive pipelines. This is a good idea in cases where you want to extend a response with data from another request. The easiest way to do this is to start a new pipeline inside the lambda function used in the `transform` function. Just remember that the lambda-function used in `transform` must return a map so it is a good idea to use `collect_response` here to convert the internal pipeline to a map. Since the `transform` function is executed asynchronously, the outer pipeline will not be affected when using `collect_response` in a pipeline inside a `transform` function.

```elixir
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
  |> response(conn)
end
```

### Advanced requests
The function `request` can either take strings (URLs) which will then be automatically transformed to a GET-request - or you can specify a map with more advanced details. The request-map reads the following keys: `:url`, `:method` which defaults to `:get`, `:body` (request payload) which defaults to the empty string and `:headers` which defaults to an empty map. You can also enter any data you want into the `:meta` map by specifying it in the `request`-map.

Note that the `request` function accepts any of the following data-types as its parameter:

* String (single URL)
* List of strings (multiple URLs)
* Map (single request)
* List of maps (multiple requests)

### Timers
Timers can be used anywhere in the pipeline to log timestamps. The timers can be used between both synchronous and asynchronous functions to determine what happens on which moments in time. On asynchronous calls which follows the protocol defined by Rackla, a log event will be triggered on every message between the Elixir processes.

```elixir
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
```

This will output information to `Logger.info`, example:

```
14:02:46.800 [info]  {1427, 288566, 800037} [meta] (Added transform function) on #PID<0.519.0>
14:02:46.800 [info]  {1427, 288566, 800160} [status] (Added transform function) on #PID<0.519.0>
14:02:46.800 [info]  {1427, 288566, 800228} [headers] (Added transform function) on #PID<0.519.0>
14:02:46.800 [info]  {1427, 288566, 800272} [chunk] (Added transform function) on #PID<0.519.0>
14:02:46.800 [info]  {1427, 288566, 800317} [done] (Added transform function) on #PID<0.519.0>
14:02:46.800 [info]  {1427, 288566, 800467} (Responded to query)
```

The message consists of (with the Logger information excluded):

```
{erlang timestamp} [message type] (optional label) Process Identifier
```

### Compression
The response can be compressed by utilizing GZip. To enable compression, set `:compress` to `true` in the keyword-list argument in the `response` function.

```elixir
response(conn, compress: true)
```

### Decompression
When executing requests to a server which replies with compressed data, you have to decompress it yourself before processing it (unless you want to send it directly to the client). If the server uses GZip-compression, then you can use the Zlib module in Erlang to decompress the body, for example by creating a `transform` lambda-function:

```elixir
transform(fn(resp) -> Dict.update!(resp, :body, &:zlib.gunzip/1) end)
```

### Working with JSON
Rackla uses [Poison](https://github.com/devinus/poison) for working with JSON internally. It is a great library which converts JSON-structures to Elixir-structures and vice versa. Poison can of course also be used in the end-points for transforming and manipulating JSON data in the pipeline.

### Working with XML (and other formats)
There is currently no special XML support (or any other format except JSON). You can request data in any format over HTTP, process it with any third-party library and respond with it - but there are no built in helper functions such as the `concatenate_json` used for JSON.

### Caching
Rackla has no built in support for caching but you can, for example, use [EchoTeams Erlang memcached client library](https://github.com/EchoTeam/mcd) which we've successfully experimented with.

### Cross-Origin Resource Sharing (CORS) 
In order to use CORS in your API gateway, you can use any tool which works with Plug such as [cors_plug](https://github.com/mschae/cors_plug).

## The MIT License (MIT)

Copyright (c) 2015 Anton Fagerberg

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.