defmodule RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts Router.init([])
  test "proxy request response" do
    conn =
      conn(:get, "/proxy/?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Content-Type") == ["application/json"]

    response = Poison.decode!(conn.resp_body)
    assert Map.has_key?(response, "foo")
    assert response["foo"] == "bar"
  end

  test "proxy request, set response header" do
    conn =
      conn(:get, "/proxy/set-headers/?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Rackla") == ["CrocodilePear"]

    response = Poison.decode!(conn.resp_body)
    assert Map.has_key?(response, "foo")
    assert response["foo"] == "bar"
  end

  test "request to json" do
    conn =
      conn(:get, "/proxy/concat-json/?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/no-header/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Content-Type") == ["application/json"]

    {decode_status, json_decoded} = Poison.decode(conn.resp_body)

    assert :ok == decode_status
    assert is_list(json_decoded)
    assert length(json_decoded) == 1

    [item | _] = json_decoded

    assert Map.has_key?(item, "body")
    assert Map.has_key?(item, "headers")
    assert Map.has_key?(item, "status")
    assert Map.has_key?(item, "meta")
  end

  test "multiple requests to json" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"
    ]

    conn =
      conn(:get, "/proxy/multi/concat-json/?#{Enum.join(urls, "|")}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Content-Type") == ["application/json"]

    {decode_status, json_decoded} = Poison.decode(conn.resp_body)

    assert :ok == decode_status
    assert is_list(json_decoded)
    assert length(json_decoded) == length(urls)


    Enum.each(json_decoded, fn(item) ->
      assert Map.has_key?(item, "body")
      assert Map.has_key?(item, "headers")
      assert Map.has_key?(item, "status")
      assert Map.has_key?(item, "meta")
    end)
  end
  
  test "multiple requests to json with mixed input (json / html)" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    ]

    conn =
      conn(:get, "/proxy/multi/concat-json/?#{Enum.join(urls, "|")}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Content-Type") == ["application/json"]

    {decode_status, json_decoded} = Poison.decode(conn.resp_body)

    assert :ok == decode_status
    assert is_list(json_decoded)
    assert length(json_decoded) == length(urls)

    Enum.each(json_decoded, fn(item) ->
      assert Map.has_key?(item, "body")
      assert Map.has_key?(item, "headers")
      assert Map.has_key?(item, "status")
      assert Map.has_key?(item, "meta")
      assert Map.has_key?(item, "error")
    end)
    
    assert json_decoded  |> Enum.at(0) |> Map.get("body") |> is_map
    assert json_decoded  |> Enum.at(1) |> Map.get("body") |> is_binary
  end
  
  test "multiple requests to json (body only) with mixed input (json / html)" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    ]

    conn =
      conn(:get, "/proxy/multi/concat-json/body-only/?#{Enum.join(urls, "|")}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Content-Type") == ["application/json"]

    {decode_status, json_decoded} = Poison.decode(conn.resp_body)

    assert :ok == decode_status
    assert is_list(json_decoded)
    assert length(json_decoded) == length(urls)
    
    assert json_decoded  |> Enum.at(0) |> is_map
    assert json_decoded  |> Enum.at(1) |> is_binary
  end

  test "proxy multiple requests to a response" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    ]

    conn =
      conn(:get, "/proxy/multi/?#{Enum.join(urls, "|")}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"

    assert String.contains?(conn.resp_body, "{\"foo\":\"bar\"}")
    assert String.contains?(conn.resp_body, "foo-bar")
  end

  test "transform blanker" do
    url = "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"

    conn =
      conn(:get, "/proxy/?#{url}")
      |> Router.call(@opts)

    assert conn.status == 200
    assert get_resp_header(conn, "Content-Type") == ["application/json"]
    assert String.length(conn.resp_body) > 0

    conn =
      conn(:get, "/proxy/transform/blanker/?#{url}")
      |> Router.call(@opts)

    assert conn.status == 404
    assert get_resp_header(conn, "Content-Type") != ["application/json"]
    assert String.length(conn.resp_body) == 0
  end

  test "transform identity" do
    url = "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"

    conn1 =
      conn(:get, "/proxy/?#{url}")
      |> Router.call(@opts)

    conn2 =
      conn(:get, "/proxy/transform/identity/?#{url}")
      |> Router.call(@opts)

    assert conn1.status == conn2.status
    assert conn1.resp_headers == conn2.resp_headers
    assert conn1.resp_body == conn2.resp_body
  end

  test "multiple transform functions" do
    val_a = "value-a"
    val_b = "value-b"
    val_c = "value-c"
    val_d = "value-d"
    
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key-a/#{val_a}",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key-b/#{val_b}",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key-c/#{val_c}",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key-d/#{val_d}"
    ]

    conn =
      conn(:get, "/proxy/transform/multi/?#{Enum.join(urls, "|")}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"

    assert String.contains?(conn.resp_body, val_a)
    assert String.contains?(conn.resp_body, val_b)
    assert String.contains?(conn.resp_body, val_c)
    assert String.contains?(conn.resp_body, val_d)
    
    assert  conn.resp_body  
    |> String.replace(val_a, "") 
    |> String.replace(val_b, "") 
    |> String.replace(val_c, "") 
    |> String.replace(val_d, "") == ""
  end

  test "compressed response" do
    conn_uncompressed =
      conn(:get, "/proxy/?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)
    
    conn_compressed =
      conn(:get, "/proxy/gzip/?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)
      
      assert conn_uncompressed.state == conn_compressed.state
      assert conn_uncompressed.status == conn_compressed.status
      assert conn_uncompressed.port == conn_compressed.port
      assert conn_uncompressed.scheme == conn_compressed.scheme
      assert conn_uncompressed.method == conn_compressed.method
      
      assert get_resp_header(conn_compressed, "content-encoding") == ["gzip"]
      assert get_resp_header(conn_uncompressed, "content-encoding") == []
      
      assert conn_uncompressed.resp_body == :zlib.gunzip(conn_compressed.resp_body)
  end
end