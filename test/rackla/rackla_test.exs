defmodule Rackla.Tests do
  use ExUnit.Case, async: true
  use Plug.Test

  import Rackla

  test "request process" do
    producer = request("http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
    assert is_pid(producer)

    send(producer, { self, :ready })

    assert_receive { ^producer, :headers, _headers }, 1_000
    assert_receive { ^producer, :status, _status }, 1_000
    assert_receive { ^producer, :meta, _meta }, 1_000
    assert_receive { ^producer, :chunk, _chunks }, 1_000
    assert_receive { ^producer, :done }, 1_000
  end

  test "request process on multiple URIs" do
    uris = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
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
    producer = request("http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar")
    response = collect_response(producer)
    assert is_map(response)

    %Rackla.Response{status: status, headers: headers, body: body, meta: meta, error: error} = response
    assert is_integer(status)
    assert is_map(headers)
    assert is_bitstring(body)
    assert is_map(meta)
    assert error == nil
    
    assert body == %{foo: "bar"} |> Poison.encode!
  end

  test "collect response to map on multiple URIs" do
    uris = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"
    ]

    producers = request(uris)

    assert is_list(producers)
    assert length(producers) == length(uris)

    Enum.each(producers, fn(producer) ->
      response = collect_response(producer)
      assert is_map(response)

      %Rackla.Response{status: status, headers: headers, body: body, meta: meta, error: error} = response
      assert is_integer(status)
      assert is_map(headers)
      assert is_bitstring(body)
      assert is_map(meta)
      assert error == nil
      
      assert body == %{foo: "bar"} |> Poison.encode!
    end)
  end
  
  test "invalid URL" do
    response = 
      "invalid-url"
      |> request
      |> collect_response
      
    assert response.error == :nxdomain
  end
  
  test "invalid transform" do
    response = 
    "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"
      |> request
      |> transform(fn(response) -> Dict.get!(:invalid, response) end)
      |> collect_response
      
    assert response.error == %UndefinedFunctionError{arity: 2, function: :get!, module: Dict, self: false}
  end
  
  test "transform single function" do
    error_msg = "custom error"
    
    response =
      "invalid-url"
      |> request
      |> transform(&(Map.update!(&1, :error, fn(_e) -> error_msg end)))
      |> collect_response
      
    assert response.error == error_msg
  end
  
  test "transform multiple functions" do
    error_msg = "custom error"
    
    [response1, response2] =
      ["invalid-url", "invalid-url2"]
      |> request
      |> transform([
          &(Map.update!(&1, :error, fn(_e) -> error_msg <> "1" end)),
          &(Map.update!(&1, :error, fn(_e) -> error_msg <> "2" end))
        ])
      |> collect_response
      
    assert response1.error == error_msg <> "1"
    assert response2.error == error_msg <> "2"
  end
    
  test "transform list with fewer functions" do
    error_msg = "custom error"
    
    [response1, response2] =
      ["invalid-url", "invalid-url2"]
      |> request
      |> transform([ &(Map.update!(&1, :error, fn(_e) -> error_msg end)) ])
      |> collect_response
      
    assert response1.error == error_msg
    assert response2.error == :nxdomain
  end
  
  test "transform list with too many functions" do
    error_msg = "custom error"
    
    [response1, response2] =
      ["invalid-url", "invalid-url2"]
      |> request
      |> transform([
          &(Map.update!(&1, :error, fn(_e) -> error_msg <> "1" end)),
          &(Map.update!(&1, :error, fn(_e) -> error_msg <> "2" end)),
          &(Map.update!(&1, :error, fn(_e) -> error_msg <> "3" end))
        ])
      |> collect_response
      
    assert response1.error == error_msg <> "1"
    assert response2.error == error_msg <> "2"
  end
  
  test "transform with JSON conversion (string return)" do
    response = 
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key/value"
      |> request
      |> transform(&(Map.update!(&1, :body, fn(body) -> body["foo"] end)), json: true)
      |> collect_response
    
    assert response.body == "bar"
  end
  
  test "transform with JSON conversion (map return)" do
    response = 
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key/value"
      |> request
      |> transform(&(Map.update!(&1, :body, fn(body) -> %{ack: body["foo"]} end)), json: true)
      |> collect_response
    
    {status, struct} = Poison.decode(response.body)
    assert status == :ok
    assert Map.keys(struct) |> length == 1
    assert Map.has_key?(struct, "ack")
    assert struct["ack"] == "bar"
  end
  
  test "transform with JSON conversion (invalid URL)" do
    response = 
      "invalid-url"
      |> request
      |> transform(&(Map.update!(&1, :body, fn(body) -> %{date: body["date"]} end)), json: true)
      |> collect_response
      
    assert response.error == %Poison.SyntaxError{message: "Unexpected end of input", token: nil}
  end
  
  test "transform with JSON conversion (invalid json)" do
    response = 
    "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
      |> request
      |> transform(&(Map.update!(&1, :body, fn(body) -> %{date: body["date"]} end)), json: true)
      |> collect_response
    
    is_poison_error = 
      case response.error do
        %Poison.SyntaxError{} -> true
        _ -> false
      end
      
    assert is_poison_error
  end
end