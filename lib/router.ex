defmodule Router do
  @moduledoc false

  use Plug.Router
  use Plug.ErrorHandler
  import Rackla

  plug :match
  plug :dispatch

  # =========================================== #
  # Below is a collection of sample end-points. #
  # =========================================== #

  # Call end-point with any URL to proxy it.
  # Example: /proxy?http://ip.jsontest.com/
  get "/proxy" do
    conn.query_string
    |> request
    |> response
  end

  # Call end-point with any URL to proxy it.
  # HTTP response code will be set to 404.
  # Example: /proxy/status/404?http://ip.jsontest.com/
  get "/proxy/status/404" do
    conn.query_string
    |> request
    |> response(status: 404)
  end

  # Call end-point with any URL to proxy it.
  # HTTP response will be compressed with GZip compression.
  # Example: /proxy/gzip?http://ip.jsontest.com/
  get "/proxy/gzip" do
    conn.query_string
    |> request
    |> response(compress: true)
  end

  # Call end-point with an arbitrary amount of URLs separated by "|".
  # Example: /proxy/multi?http://ip.jsontest.com/|http://api.openweathermap.org/data/2.5/weather?q=Malmo,se
  get "/proxy/multi" do
    String.split(conn.query_string, "|")
    |> request
    |> response
  end

  # Call end-point with an arbitrary amount of URLs separated by "|".
  # Responses will be orderd in the same order as the URLs are requested.
  # Example: /proxy/multi/sync?http://ip.jsontest.com/|http://api.openweathermap.org/data/2.5/weather?q=Malmo,se
  get "/proxy/multi/sync" do
    String.split(conn.query_string, "|")
    |> request
    |> response(sync: true)
  end

  # Call end-point with any URL to proxy it.
  # A custom header will be sent with the response.
  # Example: /proxy/set-headers?http://ip.jsontest.com/
  get "/proxy/set-headers" do
    conn.query_string
    |> request
    |> response(headers: %{"Rackla" => "CrocodilePear"})
  end

  # Call end-point with any URL to proxy it.
  # Response will be encoded in JSON format.
  # Example: /proxy/json?http://ip.jsontest.com/
  get "/proxy/json" do
    conn.query_string
    |> request
    |> response(json: true)
  end

  # Call end-point with an arbitrary amount of URLs separated by "|".
  # Response will be encoded in JSON format.
  # Example: /proxy/multi/json?http://ip.jsontest.com/|http://api.openweathermap.org/data/2.5/weather?q=Malmo,se
  get "/proxy/multi/json" do
    String.split(conn.query_string, "|")
    |> request
    |> response(json: true)
  end

  # Custom end-point which you can call with an arbitrary amount of cities
  # to get the temperatures (in Kelvin).
  # This will rewrite the JSON responses from the OpenWeatherMap API.
  # Example: /temperature?Malmo,se|Lund,se|Copenhagen,dk
  get "/temperature" do
    temperature_extractor = fn(weather_response) ->
      case Poison.decode(weather_response) do
        {:ok, json_decoded} ->
          Map.put(%{}, json_decoded["name"], json_decoded["main"]["temp"])

        {:error, reason} ->
          "Failed to execute request: #{reason}"
      end
    end

    conn.query_string
    |> String.split("|")
    |> Enum.map(&("http://api.openweathermap.org/data/2.5/weather?q=#{&1}"))
    |> request
    |> map(temperature_extractor)
    |> response(json: true, compress: true)
  end

  # Display all the images from your Instagram Feed, sent as chunks in a single
  # response. The code will first call the feed end-point, extract the URLs
  # for all the images from that response, base64 encode them and add them to
  # image tags which can be rendered directly in the browser. The image response
  # order will be nondeterministic.
  # Note! Access-token from the Instagram API is required to use this end-point.
  # Example: /instagram?<access-token>
  get "/instagram" do
    "<!doctype html><html lang=\"en\"><head></head><body>"
    |> just
    |> response

    "https://api.instagram.com/v1/users/self/feed?count=50&access_token=" <> conn.query_string
    |> request
    |> flat_map(fn(response) ->
      case response do
        {:error, error} ->
          just(error)

        _ ->
          case Poison.decode(response) do
            {:ok, json} ->
              json
              |> Map.get("data")
              |> Enum.map(&(&1["images"]["standard_resolution"]["url"]))
              |> request
              |> map(fn(img_data) ->
                case img_data do
                  {:error, error} ->
                    just(error)

                  _ ->
                    "<img src=\"data:image/jpeg;base64,#{Base.encode64(img_data)}\" height=\"150px\" width=\"150px\">"
                end
              end)

            {:error, _} ->
              just(response)
          end
      end
    end)
    |> response

    "</body></html>"
    |> just
    |> response
  end

  match _ do
   send_resp(conn, 404, "end-point not found")
  end
end