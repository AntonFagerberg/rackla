defmodule Rackla.Tests do
  use ExUnit.Case, async: true
  use Plug.Test

  import Rackla

  test "Rackla.request - single URL" do
    rackla = request("http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")

    case rackla do
      %Rackla{producers: producers} ->
        Enum.each(producers, fn(producer) ->
          send(producer, { self, :ready })

          assert_receive {^producer, _response}, 1_000
        end)

      other ->
        flunk "Expected %Rackla from request, got: #{inspect(other)}"
    end
  end

  test "Rackla.request - multiple URLs" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    ]

    rackla = request(urls)

    case rackla do
      %Rackla{producers: producers} ->
        assert length(producers) == 2

        Enum.each(producers, fn(producer) ->
          send(producer, { self, :ready })

          assert_receive {^producer, _response}, 1_000
        end)

      other ->
        flunk "Expected %Rackla from request, got: #{inspect(other)}"
    end
  end

  test "Rackla.collect - collect single response" do
    response_item =
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
      |> request
      |> collect

    assert is_map(response_item)
    assert response_item.status == 200
    assert response_item.body == "foo-bar"
    assert is_map(response_item.headers)
    assert Dict.keys(response_item) |> length == 3
  end

  test "Rackla.collect - multiple responses" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    ]

    responses =
      urls
      |> request
      |> collect

    assert is_list(responses)
    assert length(responses) == length(urls)

    Enum.each(responses, fn(response) ->
      assert is_map(response)
      assert response.status == 200
      assert is_binary(response.body)
      assert is_map(response.headers)
      assert Dict.keys(response) |> length == 3
    end)
  end

  test "Rackla.collect - multiple deterministic responses" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    ]

    [response_1, response_2] =
      urls
      |> request
      |> collect

    assert response_1.body == "{\"foo\":\"bar\"}"
    assert response_2.body == "foo-bar"
  end

  test "Rackla.map - single response" do
    response_item =
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
      |> request
      |> map(&(&1.body))
      |> collect

    assert is_binary(response_item)
    assert response_item == "foo-bar"
  end

  test "Rackla.map - mulitple responses" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar",
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    ]

    expected_response =
      Stream.repeatedly(fn -> "foo-bar" end)
      |> Stream.take(3)
      |> Enum.to_list

    response_item =
      urls
      |> request
      |> map(&(&1.body))
      |> collect

    assert is_list(response_item)
    assert response_item == expected_response
  end
  
  test "Rackla.flat_map - single resuorce" do
    response_item =
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"
      |> request
      |> flat_map(fn(_) ->
        request("http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar")
      end)
      |> map(&(&1.body))
      |> collect
      
    assert is_binary(response_item)
    assert response_item == "foo-bar"
  end
  
  test "Rackla.flat_map - deep nesting" do
    url_1 = "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"
    url_2 = "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    
    response_item =
      url_1
      |> request
      |> flat_map(fn(_) ->
        request([url_1, url_1])
        |> flat_map(fn(_) ->
          request([url_2, url_2, url_2])
        end)
      end)
      |> map(&(&1.body))
      |> collect

    expected_response =
      Stream.repeatedly(fn -> "foo-bar" end)
      |> Stream.take(6)
      |> Enum.to_list
      
    assert is_list(response_item)
    assert length(response_item) == 6
    assert response_item == expected_response
  end
  
  test "Rackla.reduce - no accumulator" do
    url = "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    
    reduce_function = 
      fn(x, acc) ->
        String.upcase(x) <> acc
      end
      
    response_item = 
      [url, url, url]
      |> request
      |> map(&(&1.body))
      |> reduce(reduce_function)
      |> collect
      
    expected_response =
      Stream.repeatedly(fn -> "foo-bar" end)
      |> Stream.take(3)
      |> Enum.to_list
      |> Enum.reduce(reduce_function)
      
    assert is_binary(response_item)
    assert response_item == expected_response
  end
  
  test "Rackla.reduce - with accumulator" do
    url = "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
    
    reduce_function = 
      fn(x, acc) ->
        String.upcase(x) <> acc
      end
    
    accumulator = ""
      
    response_item = 
      [url, url, url]
      |> request
      |> map(&(&1.body))
      |> reduce(accumulator, reduce_function)
      |> collect
      
    expected_response =
      Stream.repeatedly(fn -> "foo-bar" end)
      |> Stream.take(3)
      |> Enum.to_list
      |> Enum.reduce(accumulator, reduce_function)
      
    assert is_binary(response_item)
    assert response_item == expected_response
  end

  # test "invalid URL" do
  #   response =
  #     "invalid-url"
  #     |> request
  #     |> collect_response
  #
  #   assert response.error == :nxdomain
  # end
  #
  # test "invalid transform" do
  #   response =
  #   "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/json/foo-bar"
  #     |> request
  #     |> transform(fn(response) -> Dict.get!(:invalid, response) end)
  #     |> collect_response
  #
  #   assert response.error == %UndefinedFunctionError{arity: 2, function: :get!, module: Dict, self: false}
  # end
  # test "transform with JSON conversion (string return)" do
  #   response =
  #     "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key/value"
  #     |> request
  #     |> transform(&(Map.update!(&1, :body, fn(body) -> body["foo"] end)), json: true)
  #     |> collect_response
  #
  #   assert response.body == "bar"
  # end
  #
  # test "transform with JSON conversion (map return)" do
  #   response =
  #     "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/echo/key/value"
  #     |> request
  #     |> transform(&(Map.update!(&1, :body, fn(body) -> %{ack: body["foo"]} end)), json: true)
  #     |> collect_response
  #
  #   {status, struct} = Poison.decode(response.body)
  #   assert status == :ok
  #   assert Map.keys(struct) |> length == 1
  #   assert Map.has_key?(struct, "ack")
  #   assert struct["ack"] == "bar"
  # end
  #
  # test "transform with JSON conversion (invalid URL)" do
  #   response =
  #     "invalid-url"
  #     |> request
  #     |> transform(&(Map.update!(&1, :body, fn(body) -> %{date: body["date"]} end)), json: true)
  #     |> collect_response
  #
  #   assert response.error == %Poison.SyntaxError{message: "Unexpected end of input", token: nil}
  # end
  #
  # test "transform with JSON conversion (invalid json)" do
  #   response =
  #   "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"
  #     |> request
  #     |> transform(&(Map.update!(&1, :body, fn(body) -> %{date: body["date"]} end)), json: true)
  #     |> collect_response
  #
  #   is_poison_error =
  #     case response.error do
  #       %Poison.SyntaxError{} -> true
  #       _ -> false
  #     end
  #
  #   assert is_poison_error
  # end
end