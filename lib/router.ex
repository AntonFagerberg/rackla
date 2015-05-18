defmodule Router do
  use Plug.Router
  use Plug.ErrorHandler
  import Rackla

  plug :match
  plug :dispatch

  # =========================================== #
  # Below is a collection of sample end-points. #
  # =========================================== #

  get "/proxy" do
    conn.query_string
    |> request
    |> response
  end

  get "/proxy/gzip" do
    conn.query_string
    |> request
    |> response(compress: true)
  end

  get "/proxy/multi" do
    String.split(conn.query_string, "|")
    |> request
    |> response
  end

  get "/proxy/set-headers" do
    conn.query_string
    |> request
    |> response(headers: %{"Rackla" => "CrocodilePear"})
  end

  get "/proxy/concat-json" do
    conn.query_string
    |> request
    |> response(json: true)
  end

  get "/proxy/multi/concat-json" do
    String.split(conn.query_string, "|")
    |> request
    |> response(json: true)
  end
  
  get "/temperature" do
    temperature_extractor = fn(weather_response) ->
      json_decoded = Poison.decode(weather_response)
      Map.put(%{}, json_decoded["name"], json_decoded["main"]["temp"])
    end

    conn.query_string
    |> String.split("|")
    |> Enum.map(&("http://api.openweathermap.org/data/2.5/weather?q=#{&1}"))
    |> request
    |> map(temperature_extractor)
    |> response(json: true, compress: true)
  end
  
  #
  # Access-token from the Instagram API is required to use this end-point.
  #
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

  # =============================== #
  # API end-points used for testing #
  # =============================== #

  get "/api/json/foo-bar" do
    json = Poison.encode!(%{foo: "bar"})

    conn
    |> put_resp_header("Content-Type", "application/json")
    |> send_resp(200, json)
  end
  
  get "/api/json/no-header/foo-bar" do
    json = Poison.encode!(%{foo: "bar"})
    send_resp(conn, 200, json)
  end

  get "/api/text/foo-bar" do
    send_resp(conn, 200, "foo-bar")
  end
  
  post "/api/text/foo-bar" do
    send_resp(conn, 200, "foo-bar-post")
  end
  
  put "/api/text/foo-bar" do
    send_resp(conn, 200, "foo-bar-put")
  end

  get "/api/echo/:key/:value" do
    json = Map.put(%{foo: "bar", baz: "qux"}, key, value) |> Poison.encode!

    conn
    |> put_resp_header("Content-Type", "application/json")
    |> send_resp(200, json)
  end

  match _ do
   send_resp(conn, 404, "end-point not found")
  end
end