defmodule TestRouter do
  @moduledoc false

  use Plug.Router
  import Rackla

  plug :match
  plug :dispatch

  get "/test/proxy" do
    conn.query_string
    |> request
    |> response
  end

  get "/test/proxy/404" do
    conn.query_string
    |> request
    |> response(status: 404)
  end

  get "/test/proxy/multi" do
    conn.query_string
    |> String.split("|")
    |> request
    |> response
  end

  get "/test/proxy/multi/sync" do
    conn.query_string
    |> String.split("|")
    |> request
    |> response(sync: true)
  end

  get "/test/proxy/gzip" do
    conn.query_string
    |> request
    |> response(compress: true)
  end
  
  get "/test/proxy/gzip/force" do
    conn.query_string
    |> request
    |> response(compress: :force)
  end

  get "/test/json" do
    just(%{foo: "bar"})
    |> response(json: true)
  end

  get "/test/proxy/set-headers" do
    conn.query_string
    |> request
    |> response(headers: %{"rackla" => "CrocodilePear"})
  end

  get "/test/json/multi" do
    just(%{foo: "bar"})
    |> join(just("hello!"))
    |> join(just(1))
    |> join(just([1.0, 2.0, 3.0]))
    |> response(json: true)
  end
  
  get "/test/redirect/:retires" do
    {retries, _} = Integer.parse(retires)

    if retries == 0 do
      send_resp(conn, 200, "redirect done!")
    else
      just("redirect body")
      |> response(status: 301, headers: %{"location" => "/test/redirect/#{retries - 1}"})
    end
  end
  
  post "/test/post-redirect/:retires" do
    {retries, _} = Integer.parse(retires)
    
    if retries == 0 do
      send_resp(conn, 200, "post redirect done!")
    else
      just("post redirect body")
      |> response(status: 301, headers: %{"location" => "/test/post-redirect/#{retries - 1}"})
    end
  end
  
  post "/test/incoming_request_with_options" do
    {:ok, rackla_request} = incoming_request(%{connect_timeout: 1337})
    
    rackla_request
    |> Poison.encode!
    |> just
    |> response
  end
  
  
  get "/test/incoming_request" do
    {:ok, rackla_request} = incoming_request()
    
    rackla_request
    |> Poison.encode!
    |> just
    |> response
  end

  get "/api/json/foo-bar" do
    json = Poison.encode!(%{foo: "bar"})

    conn
    |> put_resp_content_type("application/json")
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
    |> put_resp_content_type("application/json")
    |> send_resp(200, json)
  end

  get "/api/timeout" do
    :timer.sleep(2_000)
    send_resp(conn, 200, "ok")
  end
end