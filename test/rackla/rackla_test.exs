defmodule Rackla.Tests do
  use ExUnit.Case, async: true
  use Plug.Test

  import Rackla

  test "request process" do
    producers = request("http://validate.jsontest.com/?json={%22key%22:%22value%22}")
    assert is_list(producers)
    assert length(producers) == 1

    Enum.each(producers, fn(producer) ->
      send(producer, { self, :ready })

      assert_receive { ^producer, :headers, _headers }, 1_000
      assert_receive { ^producer, :status, _status }, 1_000
      assert_receive { ^producer, :meta, _meta }, 1_000
      assert_receive { ^producer, :chunk, _chunks }, 1_000
      assert_receive { ^producer, :done }, 1_000
    end)
  end

  test "request process on multiple URIs" do
    uris = [
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}",
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}"
    ]

    producers = request(uris)
    assert is_list(producers)
    assert length(producers) == length(uris)

    Enum.each(producers, fn(producer) ->
      send(producer, { self, :ready })
      assert_receive { ^producer, :headers, _headers }, 1_000
      assert_receive { ^producer, :status, _status }, 1_000
      assert_receive { ^producer, :meta, _meta }, 1_000
      assert_receive { ^producer, :chunk, _chunks }, 1_000
      assert_receive { ^producer, :done }, 1_000
    end)
  end

  test "collect response to map" do
    [producer | _] = request("http://validate.jsontest.com/?json={%22key%22:%22value%22}")

    map = collect_response(producer)
    assert is_map(map)

    %{status: status, headers: headers, body: body, meta: meta} = map
    assert is_integer(status)
    assert is_map(headers)
    assert is_bitstring(body)
    assert is_map(meta)
  end

  test "collect response to map on multiple URIs" do
    uris = [
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}",
      "http://validate.jsontest.com/?json={%22key%22:%22value%22}"
    ]

    producers = request(uris)

    assert is_list(producers)
    assert length(producers) == length(uris)

    Enum.each(producers, fn(producer) ->
      map = collect_response(producer)
      assert is_map(map)

      %{status: status, headers: headers, body: body, meta: meta} = map
      assert is_integer(status)
      assert is_map(headers)
      assert is_bitstring(body)
      assert is_map(meta)
    end)
  end
  
  test "invalid URL meta error" do
    response = 
      "invalid-url"
      |> request
      |> collect_response
      |> Enum.at(0)
      
    assert Dict.get(response, :status) == 500
    assert Dict.has_key?(response, :meta)
    
    meta_map = Dict.get(response, :meta)

    assert is_map(meta_map)
    assert Dict.has_key?(meta_map, :error)
    assert Dict.get(meta_map, :error) == :nxdomain
  end
end