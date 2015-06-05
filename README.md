# Rackla

Rackla is an open source framework for building API gateways. When we say API gateway, we mean to proxy and potentially enhance the communication by transforming the data sent over HTTP between servers and  clients (such as browsers). The communication can be enhanced by throwing away unnecessary data, concatenating multiple requests into a single request or converting the data between different formats. Another possibility is to change existing APIs so that they work in a different way, or merge any amount of existing APIs into a single new one.

![API Gateway](http://www.antonfagerberg.com/images/projects/api-gateway.png)

With Rackla, you can asynchronously execute multiple HTTP-requests and transform them in any way you want. The results, encapsulated in the `Rackla` type, can be transformed with well known functions such as `map`, `flat_map` and `reduce`. By using the pipe operator in Elixir, you can express your new API end-points as pipelines which start with requests that are piped in to transforming functions and finally piped into a response.

Rackla utilizes [Plug](https://github.com/elixir-lang/plug) to expose new end-points and communicate with clients over HTTP. Internally, it uses [Hackney](https://github.com/benoitc/hackney) to make HTTP requests and [Poison](https://github.com/devinus/poison) for dealing with JSON. A big thank you to everyone involved in these projects!

## Minimal installation (as Mix dependency)

This will be published soon!

## Full installation (clone example project)

You can clone [this GitHub repository](https://github.com/AntonFagerberg/rackla) in order to get a complete working API gateway with runnable example end-points and tests. The cloned project includes all "infrastructure" needed to easily expose (run) your end-points or deploy your API gateway to a cloud service such as Heroku. 

### Starting the application
The application will be started automatically when running `iex -S mix` from the project root. You can also start it by running `mix server`. By default, it will start on port 4000, but you can change the port either from the file `config/config.exs` or by creating an environment variable named `PORT`.

### Deploy to Heroku
The [Heroku Buildpack for Elixir](https://github.com/HashNuke/heroku-buildpack-elixir) works out of the box for Rackla when doing a full installation.

## Example usages

### OpenWeatherMap API (JSON)

OpenWeatherMap has an API with the following end-point that we're going to use: `http://api.openweathermap.org/data/2.5/weather?q=Malmo,SE`. That end-point lets us specify one city to retrieve weather data from, defined by: `?q=Malmo,SE` (found at the end of the URL). 

This will return the weather data for Malmö in Sweden:

```json
{
  "coord":{
    "lon":13,
    "lat":55.6
  },
  "sys":{
    "message":0.0071,
    "country":"Sweden",
    "sunrise":1432262690,
    "sunset":1432322670
  },
  "weather":[
    {
       "id":802,
       "main":"Clouds",
       "description":"scattered clouds",
       "icon":"03d"
    }
  ],
  "base":"stations",
  "main":{
    "temp":288.737,
    "temp_min":288.737,
    "temp_max":288.737,
    "pressure":1030.12,
    "sea_level":1035.87,
    "grnd_level":1030.12,
    "humidity":58
  },
  "wind":{
    "speed":5.36,
    "deg":248.501
  },
  "clouds":{
    "all":36
  },
  "dt":1432303003,
  "id":2712995,
  "name":"Malmo",
  "cod":200
}
```

What we're interested in is the `temp` value stored in `main`, and the `name` field.
The goal with the new end-point in our API gateway is to take an arbitrary amount of cities
separated by `|` in the query string, such as: `/temperature?malmo,se|halmstad,se|copenhagen,dk|san francisco,us|stockholm,se` and return a list of temperatures for these cities.

We want our JSON response to look like this:

```json
[
   {
      "Malmo":289.751
   },
   {
      "Halmstad":286.751
   },
   {
      "Copenhagen":287.487
   },
   {
      "San Francisco":285.087
   },
   {
      "Stockholm":288.801
   }
]
```

And this is how the code in Rackla will look like (explained below):
```elixir
get "/temperature" do
  temperature_extractor = fn(http_response) ->
    case http_response do
      {:error, reason} ->
        "HTTP request failed because: #{reason}"
      
      ok_response ->
        case Poison.decode(ok_response) do
          {:ok, json_decoded} ->
            Map.put(%{}, json_decoded["name"], json_decoded["main"]["temp"])

          {:error, reason} ->
            "Failed to decode response because: #{inspect(reason)}"
        end
    end
  end

  conn.query_string
  |> String.split("|")
  |> Enum.map(&("http://api.openweathermap.org/data/2.5/weather?q=#{&1}"))
  |> Rackla.request
  |> Rackla.map(temperature_extractor)
  |> Rackla.response(json: true, compress: true)
end
```

Let us walk through the code and explain what is happening here. First we define our endpoint `/temperature` as we would normally do in Plug. Then we define a function which we'll use in the `Rackla.map` function in the pipeline, let's get back to it later and first look at the pipeline defined at the bottom of our end-point.

Here's what the pipeline will do:

 * Get the query string from `conn` (implicitly provided by Plug), in this example it will be the string: `"malmo,se|halmstad,se|copenhagen,dk|san francisco,us|stockholm,se"`.
 * Split the string on `|` to get a list instead: `["malmo,se", "halmstad,se", "copenhagen,dk", "san francisco,us", "stockholm,se"]`.
 * Map over the list and convert the city strings into a list of URLs to the OpenWeatherMap API.
 * Request all URLs, this will return a `Rackla` type which will contain (when ready) the response or an `:error` tuple on failure for each URL.
 * Map over the results using our function `temperature_extractor` (explained below).
 * Respond to the client. We use the options `:json` to encode our response in JSON format and set the appropriate headers (this will take the Elixir map type returned in `temperature_extractor` and convert it to a JSON map and put all responses in a JSON list). We can also use `:compress` in order to compress the result with gzip compression (when `:compress` is `true`, Rackla will check the request headers to make sure that the client accepts gzip - you can also set it to `:force` to always respond with gzip).
 
So let's walk through what the function `temperature_extractor` does. First of all, we pattern match to make sure that our HTTP request hasn't failed. If it has failed, we simply return a string with the reason for the failure. If our HTTP request has succeed, we try to decode it from JSON format using the library Poison. If the decoding is successful, we create a new Elixir map containing the name and the temperature for the response. This will be, for example, `%{"Malmo" => 289.751}` in one of the responses. The `response` function will later be able to encode this Elixir map into a JSON map automatically.

Done! That's all we need to do to make it work!

### Instagram (Base64 encoded images)
In this example, we will instead of providing an API, actually serve an entire HTML page that we can view in our browser. While serving a full HTML page is not really Rackla's main goal, this example illustrates how we can make recursive requests and work with chunked responses.

```elixir
get "/instagram" do
  "<!doctype html><html lang=\"en\"><head></head><body>"
  |> Rackla.just
  |> Rackla.response

  "https://api.instagram.com/v1/users/self/feed?count=50&access_token=" <> conn.query_string
  |> Rackla.request
  |> Rackla.flat_map(fn(response) ->
    case response do
      {:error, error} ->
        Rackla.just(error)

      _ ->
        case Poison.decode(response) do
          {:ok, json} ->
            json
            |> Map.get("data")
            |> Enum.map(&(&1["images"]["standard_resolution"]["url"]))
            |> Rackla.request
            |> Rackla.map(fn(img_data) ->
              case img_data do
                {:error, error} ->
                  error

                _ ->
                  "<img src=\"data:image/jpeg;base64,#{Base.encode64(img_data)}\" height=\"150px\" width=\"150px\">"
              end
            end)

          {:error, _} ->
            Rackla.just(response)
        end
    end
  end)
  |> Rackla.response

  "</body></html>"
  |> Rackla.just
  |> Rackla.response
end
```
    
Once again, let's go through the code to see what is happening. We start by exposing the end-point `/instagram` as we normally do in Plug. Then we define the first of three pipelines. We store some HTML code in a string, convert it into a `Rackla` type with the function `just` and use `response` to send it to the client. 

After we've responded with the HTML code, we can move on to the big middle pipeline. In it, we will call the an Instagram API end-point - the actual response can be seen here: [instagram.com/developer/endpoints/users/#get_users_feed](https://instagram.com/developer/endpoints/users/#get_users_feed). We have to pass an access token to the Instagram API so we let the user supply it via the query string in the browser and add it to the Instagram URL. We call `request` with the URL and then use `flat_map`. The reason for using `flat_map` is because it gives us an easy way to create new requests based on the responses from previous requests. 

If we get a response from the Instagram API, we decode it from JSON format to an Elixir data structure with Poison. We then extract the list stored in the key `"data"` in the Instagram response. This will give us a list of items from our Instagram feed. We then map over these items and extract the URL for the images in standard resolution which will give us a list of URLs pointing to images. We can now pipe this list in to the `request` function to fetch all these images. 

Now, we map over the results - the results will now be binary image data! We can take this binary image data, Base64 encode it and place it inside a HTML image tag. By doing so, the browser can render the response chunks as images directly on our page. In the the "outer" pipeline, we end it with the `response` function which will send the HTML image tags to the client, in this case the browser. (It is important to notice that `response` is only used in the outer pipeline and not in the inner pipeline created inside `flat_map`).

Finally, we create the last pipeline which will send the closing HTML tags.

What is cool about this approach is that the image requests are executed concurrently. This means that the image HTML tags will be sent to the client as soon as they are available (as soon as we get a response from any of the image requests). We only make one request to our API gateway from the client and we only send one response to the client from our API gateway but the images will be sent in chunks so they will show up one after another in the browser just like if we requested them individually.

We will also notice, in this example, that the order is nondeterministic - meaning that we will (most likely) get a different order in which the images are sent every time we refresh the page. If we wanted to preserve the ordering of the images, we could either send the ordering with the chunks and let the client code render the images on the correct position - or we could set the `:sync` option to `true` in `response` which would then wait for the responses and then send them in the appropriate order.

### More examples
A collection of smaller example end-points can be found in found [lib/rackla/rackla.ex](https://github.com/AntonFagerberg/rackla/blob/master/lib/router.ex) which illustrates additional techniques that can be used in Rackla.

## The Rackla type
`Rackla` is also the name of the type used in all of Rackla's functions. Internally, it consists of a list of Elixir processes which communicate with message passing according to a protocol defined inside Rackla (these processes can themselves contain even more nested `Rackla` types). The `Rackla` type should never be modified directly!

The `Rackla` type is created with `request` which converts one or many HTTP requests to a single `Rackla` type. You can also encapsulate normal Elixir types in a `Rackla` type with the functions `just` or `just_list`.

Most functions, like `map`, `flat_map` and `reduce`, defined in Rackla will take a `Rackla` type and return a new `Rackla` type.

The `response` function converts the `Rackla` type to a HTTP response which is sent to the client by utilizing `Plug`. You can also convert a `Rackla` type into "normal" Elixir types with the function `collect`.

It is important to note that once a `Rackla` type has been used, it is no longer valid:

```elixir
a = Rackla.just(1)
b = a |> Rackla.map(&(&1 + 1))
# a is now "dead" and can't be used anymore
```

Under normal circumstances, the `Rackla` type should be "invisible". Think of it as the box which the data is transported inside and that all the functions you use automatically opens the box, takes out the value for you and then puts it in a new box when you're done with it.

(Or simply think of it as a monad if you're comfortable with that.)

## Function overview

### request
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

### map
Returns a new `Rackla` type, where each encapsulated item is the result of 
invoking `fun` on each corresponding encapsulated item.

Example:
```elixir
Rackla.just_list([1,2,3]) |> Rackla.map(fn(x) -> x * 2 end) |> Rackla.collect
[2, 4, 6]
```
    
### flat_map
Takes a `Rackla` type, applies the specified function to each of the 
elements encapsulated in it and returns a new `Rackla` type with the 
results. The given function must return a `Rackla` type.

This function is useful when you want to create a new request pipeline based
on the results of a previous request. In those cases, you can use 
`Rackla.flat_map` to access the response from a request and call 
`Rackla.request` inside the function since `Rackla.request` returns a 
`Rackla` type.

Example:
```elixir
Rackla.just_list([1,2,3]) |> Rackla.flat_map(fn(x) -> Rackla.just(x * 2) end) |> Rackla.collect
[2, 4, 6]
```  

### reduce
Invokes `fun` for each element in the `Rackla` type passing that element and
the accumulator `acc` as arguments. `fun`s return value is stored in `acc`. The 
first element of the collection is used as the initial value of `acc` (you can 
also use `Rackla.reduce/3` and specify your own accumulator). Returns the 
accumulated value inside a `Rackla` type.

Example:
```elixir
Rackla.just_list([1,2,3]) |> Rackla.reduce(fn (x, acc) -> x + acc end) |> Rackla.collect
6
```

### just
Takes any type an encapsulates it in a `Rackla` type.

Example:
```elixir
Rackla.just([1,2,3]) |> Rackla.map(&IO.inspect/1)
[1, 2, 3]
```

### just_list
Takes a list of and encapsulates each of the containing elements separately 
in a `Rackla` type.

Example:
```elixir
Rackla.just_list([1,2,3]) |> Rackla.map(&IO.inspect/1)
3
2
1
```

### collect
Returns the element encapsulated inside a `Rackla` type, or a list of 
elements in case the `Rackla` type contains many elements.

Example:
```elixir
Rackla.just_list([1,2,3]) |> Rackla.collect
[1,2,3]
```

### join
Returns a new `Rackla` type by joining the encapsulated elements from two
`Rackla` types.

Example:
```elixir
Rackla.join(Rackla.just(1), Rackla.just(2)) |> Rackla.collect
[1, 2]
```
    
### response
Converts a `Rackla` type to a HTTP response and send it to the client by
using `Plug.Conn`. The `Plug.Conn` will be taken implicitly by looking for a 
variable named `conn`. If you want to specify which `Plug.Conn` to use, you 
can use `Rackla.response_conn`.

Strings will be sent as is to the client. If the `Rackla` type contains any 
other type such as a list, it will be converted into a string by using `inspect`
on it. You can also convert Elixir data types to JSON format by setting the
option `:json` to true.

Using this macro is the same as writing:
    `conn = response_conn(rackla, conn, options)`

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
 the header "Content-Type" to the appropriate "application/json; charset=utf-8".

## License
Rackla source code is released under Apache 2 License. Check LICENSE file for more information.
