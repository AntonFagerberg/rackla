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

  get "/test/json" do
    just(%{foo: "bar"})
    |> response(json: true)
  end

  get "/test/proxy/set-headers" do
    conn.query_string
    |> request
    |> response(headers: %{"Rackla" => "CrocodilePear"})
  end

  get "/test/json/multi" do
    just(%{foo: "bar"})
    |> join(just("hello!"))
    |> join(just(1))
    |> join(just([1.0, 2.0, 3.0]))
    |> response(json: true)
  end

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

  get "/api/timeout" do
    :timer.sleep(2_000)
    send_resp(conn, 200, "ok")
  end
end