defmodule Rackla.Tests do
  use ExUnit.Case, async: true
  use Plug.Test

  import Rackla
  
  # TODO tests
  # - Timeouts
  # - HTTP verbs (delete etc)
  
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
  
  test "Rackla.collect - collect single response (PUT)" do
    response_item =
      %{method: :put, url: "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"}
      |> request
      |> collect

    assert is_map(response_item)
    assert response_item.status == 200
    assert response_item.body == "foo-bar-put"
    assert is_map(response_item.headers)
    assert Dict.keys(response_item) |> length == 3
  end
  
  test "Rackla.collect - collect single response (POST)" do
    response_item =
      %{method: :post, url: "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar"}
      |> request
      |> collect

    assert is_map(response_item)
    assert response_item.status == 200
    assert response_item.body == "foo-bar-post"
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
  
  test "Rackla.reduce - numeric" do
    reduce_function = 
      fn(x, acc) ->
        x + acc
      end
      
    input = [1, 2, 3, 4, 5]
      
    response_item = 
      input
      |> just_list
      |> reduce(reduce_function)
      |> collect
      
    expected_response = Enum.reduce(input, reduce_function)

    assert is_number(response_item)
    assert response_item == expected_response
  end
  
  test "Rackla.response - invalid URL" do
    response_item =
      "invalid-url"
      |> request
      |> collect
    
    assert response_item == {:error, :nxdomain}
  end
  
  test "Rackla.response - valid and invalid URL" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar",
      "invalid-url"
    ]
    
    [response_1, response_2] =
      urls
      |> request
      |> collect
    
    assert is_map(response_1)
    assert response_1.status == 200
    assert response_1.body == "foo-bar"
    assert is_map(response_1.headers)
    assert Dict.keys(response_1) |> length == 3
    
    assert response_2 == {:error, :nxdomain}
  end
  
  test "Rackla.map - valid and invalid URL" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar",
      "invalid-url"
    ]
    
    [response_1, response_2] =
      urls
      |> request
      |> map(fn(response) ->
        case response do
          {:error, term} -> term
          %{body: body} -> body
        end
      end)
      |> collect
      
    assert response_1 == "foo-bar"
    assert response_2 == :nxdomain
  end
  
  test "Rackla.flat_map - valid and invalid URL (variation 1)" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar",
      "invalid-url"
    ]
    
    [response_1, response_2] =
      just("test")
      |> flat_map(fn(_) ->
        request(urls)
      end)
      |> map(fn(response) ->
        case response do
          {:error, term} -> term
          %{body: body} -> body
        end
      end)
      |> collect
      
    assert response_1 == "foo-bar"
    assert response_2 == :nxdomain
  end
  
  test "Rackla.flat_map - valid and invalid URL (variation 2)" do
    urls = [
      "http://localhost:#{Application.get_env(:rackla, :port, 4000)}/api/text/foo-bar",
      "invalid-url"
    ]
    
    [response_1, response_2] =
      just("test")
      |> flat_map(fn(_) ->
        request(urls)
        |> map(fn(response) ->
          case response do
            {:error, term} -> term
            %{body: body} -> body
          end
        end)
      end)
      |> collect
      
    assert response_1 == "foo-bar"
    assert response_2 == :nxdomain
  end
  
  test "Rackla.map - raising exceptions" do
    response_item = 
      just("test")
      |> map(fn(_) -> raise "ops" end)
      |> collect
      
    assert response_item == {:error, %RuntimeError{message: "ops"}}
  end
  
  test "Rackla.map - arithmetic error" do
    response_item = 
      just("test")
      |> map(fn(_) -> 1/0 end)
      |> collect
      
    assert response_item == {:error, %ArithmeticError{}}
  end
  
  test "Rackla.flat_map - wrong return type" do
    response_item = 
      just("test")
      |> flat_map(fn(_) -> "not a Rackla struct" end)
      |> collect
      
    assert response_item == {:error, %MatchError{term: "not a Rackla struct"}}
  end
  
  test "Rackla.map - raising exceptions" do
    response_item = 
      just("test")
      |> flat_map(fn(_) -> raise "ops" end)
      |> collect
      
    assert response_item == {:error, %RuntimeError{message: "ops"}}
  end
  
  test "Rackla.flat_map - arithmetic error" do
    response_item = 
      just("test")
      |> flat_map(fn(_) -> 1/0 end)
      |> collect
      
    assert response_item == {:error, %ArithmeticError{}}
  end
end