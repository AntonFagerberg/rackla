defmodule RouterTest do
  use ExUnit.Case, async: true
  use Plug.Test

  @opts Router.init([])

  test "Proxy" do
    conn =
      :get
      |> conn("/test/proxy?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert conn.resp_body == "foo-bar"
  end

  test "Proxy - set status" do
    conn =
      :get
      |> conn("/test/proxy/404?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 404
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert conn.resp_body == "foo-bar"
  end

  test "Proxy - set headers" do
    conn =
      :get
      |> conn("/test/proxy/set-headers?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)

      assert conn.state == :chunked
      assert conn.status == 200
      assert conn.scheme == :http
      assert conn.method == "GET"
      assert conn.resp_body == "foo-bar"
      assert get_resp_header(conn, "Rackla") == ["CrocodilePear"]
  end

  test "Proxy - multi async" do
    conn =
      :get
      |> conn("/test/proxy/multi?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/timeout|http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert conn.resp_body == "foo-barok"
  end

  test "Proxy - multi sync" do
    conn =
      :get
      |> conn("/test/proxy/multi/sync?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/timeout|http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert conn.resp_body == "okfoo-bar"
  end
  test "Proxy with compression" do
    conn =
      :get
      |> conn("/test/proxy/gzip?http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert :zlib.gunzip(conn.resp_body) == "foo-bar"
    assert get_resp_header(conn, "Content-Encoding") == ["gzip"]
  end

  test "Proxy with single JSON" do
    conn =
      :get
      |> conn("/test/json")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert conn.resp_body == Poison.encode!(%{foo: "bar"})
    assert get_resp_header(conn, "Content-Type") == ["application/json"]
  end

  test "Proxy with JSON list" do
    conn =
      :get
      |> conn("/test/json/multi")
      |> Router.call(@opts)

    assert conn.state == :chunked
    assert conn.status == 200
    assert conn.scheme == :http
    assert conn.method == "GET"
    assert conn.resp_body == Poison.encode!([%{foo: "bar"}, "hello!", 1, [1.0, 2.0, 3.0]])
    assert get_resp_header(conn, "Content-Type") == ["application/json"]
  end
end