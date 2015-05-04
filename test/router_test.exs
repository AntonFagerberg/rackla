defmodule RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts Router.init([])

  test "proxy request response" do
    conn =
      conn(:get, "/proxy/?http://validate.jsontest.com/?json={%22key%22:%22value%22}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Content-Type") == ["application/json; charset=ISO-8859-1"]

    json_response = Poison.decode!(conn.resp_body)
    assert json_response["empty"] == false
    assert json_response["object_or_array"] == "object"
    assert json_response["size"] == 1
    assert json_response["validate"] == true
  end

  test "proxy request, set response header" do
    conn =
      conn(:get, "/proxy/set-headers/?http://validate.jsontest.com/?json={%22key%22:%22value%22}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert get_resp_header(conn, "Rackla") == ["CrocodilePear"]

    json_response = Poison.decode!(conn.resp_body)
    assert json_response["empty"] == false
    assert json_response["object_or_array"] == "object"
    assert json_response["size"] == 1
    assert json_response["validate"] == true
  end

  test "request to json" do
    conn =
      conn(:get, "/proxy/concat-json/?http://validate.jsontest.com/?json={%22key%22:%22value%22}")
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
    uris = [
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}",
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}"
    ]

    conn =
      conn(:get, "/proxy/multi/concat-json/?#{Enum.join(uris, "|")}")
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
    assert length(json_decoded) == length(uris)


    Enum.each(json_decoded, fn(item) ->
      assert Map.has_key?(item, "body")
      assert Map.has_key?(item, "headers")
      assert Map.has_key?(item, "status")
      assert Map.has_key?(item, "meta")
    end)
  end
  
  test "multiple requests to json with mixed input (json / html)" do
    uris = [
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}",
      "http://www.google.com"
    ]

    conn =
      conn(:get, "/proxy/multi/concat-json/?#{Enum.join(uris, "|")}")
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
    assert length(json_decoded) == length(uris)

    Enum.each(json_decoded, fn(item) ->
      assert Map.has_key?(item, "body")
      assert Map.has_key?(item, "headers")
      assert Map.has_key?(item, "status")
      assert Map.has_key?(item, "meta")
    end)

    assert (json_decoded |> Enum.at(0) |> Map.get("body") |> is_map && json_decoded |> Enum.at(1) |> Map.get("body") |> is_bitstring) || (json_decoded |> Enum.at(1) |> Map.get("body") |> is_map && json_decoded |> Enum.at(0) |> Map.get("body") |> is_bitstring)
  end
  
  test "multiple requests to json (body only) with mixed input (json / html)" do
    uris = [
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}",
      "http://www.google.com"
    ]

    conn =
      conn(:get, "/proxy/multi/concat-json/body-only/?#{Enum.join(uris, "|")}")
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
    assert length(json_decoded) == length(uris)
    assert (json_decoded |> Enum.at(0) |> is_map && json_decoded |> Enum.at(1) |> is_bitstring) || (json_decoded |> Enum.at(1) |> is_map && json_decoded |> Enum.at(0) |> is_bitstring)
  end

  test "proxy multiple requests to a response" do
    uris = [
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}",
      "http://ip.jsontest.com/",
      "http://echo.jsontest.com/key/value/one/two",
      "http://date.jsontest.com/"
    ]

    conn =
      conn(:get, "/proxy/multi/?#{Enum.join(uris, "|")}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"

    assert String.contains?(conn.resp_body, "ip")
    assert String.contains?(conn.resp_body, "milliseconds_since_epoch")
    assert String.contains?(conn.resp_body, "validate")
    assert String.contains?(conn.resp_body, "two")
  end

  test "transform blanker" do
    uri = "http://validate.jsontest.com/?json={%22key%22:%22value%22}"

    conn =
      conn(:get, "/proxy/?#{uri}")
      |> Router.call(@opts)

    assert conn.status == 200
    assert length(conn.resp_headers) > 1
    assert String.length(conn.resp_body) > 0

    conn =
      conn(:get, "/proxy/transform/blanker/?#{uri}")
      |> Router.call(@opts)

    assert conn.status == 404
    assert length(conn.resp_headers) == 1
    assert String.length(conn.resp_body) == 0
  end

  test "transform identity" do
    uri = "http://headers.jsontest.com/"

    conn1 =
      conn(:get, "/proxy/?#{uri}")
      |> Router.call(@opts)
      |> delete_resp_header("Date")

    conn2 =
      conn(:get, "/proxy/transform/identity/?#{uri}")
      |> Router.call(@opts)
      |> delete_resp_header("Date")

    assert conn1.status == conn2.status
    assert conn1.resp_headers == conn2.resp_headers
    assert conn1.resp_body == conn2.resp_body
  end

  test "multiple transform functions" do
    uris = [
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}",
      "http://ip.jsontest.com/",
      "http://echo.jsontest.com/key/value/one/two",
      "http://date.jsontest.com/"
    ]

    conn =
      conn(:get, "/proxy/transform/multi/?#{Enum.join(uris, "|")}")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert conn.resp_body == "truetruetruetrue"
  end

  test "transform json concatenated requests" do
    conn =
      conn(:get, "/temperature/?malmo,se|halmstad,se|copenhagen,dk|san francisco,us|stockholm,se")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.port == 80
    assert conn.scheme == :http
    assert conn.method == "GET"

    response = Poison.decode!(conn.resp_body)

    assert length(response) == 5
    assert Enum.any?(response, &(Map.keys(&1) == ["Malmo"]))
    assert Enum.any?(response, &(Map.keys(&1) == ["Halmstad"]))
    assert Enum.any?(response, &(Map.keys(&1) == ["Copenhagen"]))
    assert Enum.any?(response, &(Map.keys(&1) == ["San Francisco"]))
    assert Enum.any?(response, &(Map.keys(&1) == ["Stockholm"]))
  end
  
  test "compressed response" do
    conn_uncompressed =
      conn(:get, "/proxy/?http://ip.jsontest.com/")
      |> Router.call(@opts)
    
    conn_compressed =
      conn(:get, "/proxy/gzip/?http://ip.jsontest.com/")
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