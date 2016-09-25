defmodule Rackla.Tests do
  use ExUnit.Case, async: false
  use Plug.Test

  import Rackla
  import ExUnit.CaptureIO

  @test_router_port 4444
  Plug.Adapters.Cowboy.http(TestRouter, [], port: @test_router_port)

  test "Rackla.request - single URL" do
    rackla = request("http://localhost:#{@test_router_port}/api/text/foo-bar")

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
      "http://localhost:#{@test_router_port}/api/json/foo-bar",
      "http://localhost:#{@test_router_port}/api/text/foo-bar"
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
      "http://localhost:#{@test_router_port}/api/text/foo-bar"
      |> request(full: true)
      |> collect

    case response_item do
      %Rackla.Response{status: status, headers: headers, body: body} ->
        assert status == 200
        assert body == "foo-bar"
        assert is_map(headers)
      _ -> flunk("Expected Rackla.Response, got: #{inspect(response_item)}")
    end
  end
  
  test "Rackla.collect - request specific :full == true" do
    [only_body, full] =
      [
        "http://localhost:#{@test_router_port}/api/text/foo-bar",
        %Rackla.Request{
          url: "http://localhost:#{@test_router_port}/api/text/foo-bar",
          options: %{full: true}
        }
      ]
      |> request
      |> collect

    assert is_binary(only_body)
    
    case full do
      %Rackla.Response{} -> :ok
      _ -> flunk("Expected Rackla.Response, got #{inspect(full)}")
    end
  end
  
  test "Rackla.collect - request specific :full == false" do
    [only_body, full] =
      [
        %Rackla.Request{
          url: "http://localhost:#{@test_router_port}/api/text/foo-bar",
          options: %{full: false}
        },
        "http://localhost:#{@test_router_port}/api/text/foo-bar"
      ]
      |> request(full: true)
      |> collect

    assert is_binary(only_body)
    
    case full do
      %Rackla.Response{} -> :ok
      _ -> flunk("Expected Rackla.Response, got #{inspect(full)}")
    end
  end  
  
  test "Rackla.collect - collect single response (PUT)" do
    response_item =
      %Rackla.Request{method: :put, url: "http://localhost:#{@test_router_port}/api/text/foo-bar"}
      |> request(full: true)
      |> collect

    case response_item do
      %Rackla.Response{status: status, headers: headers, body: body} ->
        assert status == 200
        assert body == "foo-bar-put"
        assert is_map(headers)
      _ -> flunk("Expected Rackla.Response, got: #{inspect(response_item)}")
    end
  end

  test "Rackla.collect - collect single response (POST)" do
    response_item =
      %Rackla.Request{method: :post, url: "http://localhost:#{@test_router_port}/api/text/foo-bar"}
      |> request(full: true)
      |> collect

    case response_item do
      %Rackla.Response{status: status, headers: headers, body: body} ->
        assert status == 200
        assert body == "foo-bar-post"
        assert is_map(headers)
      _ -> flunk("Expected Rackla.Response, got: #{inspect(response_item)}")
    end
  end

  test "Rackla.collect - multiple responses" do
    urls = [
      "http://localhost:#{@test_router_port}/api/json/foo-bar",
      "http://localhost:#{@test_router_port}/api/text/foo-bar"
    ]

    responses =
      urls
      |> request(full: true)
      |> collect

    assert is_list(responses)
    assert length(responses) == length(urls)

    Enum.each(responses, fn(response) ->
      case response do
        %Rackla.Response{status: status, headers: headers, body: body} ->
          assert status == 200
          assert is_binary(body)
          assert is_map(headers)
        _ -> flunk("Expected Rackla.Response, got: #{inspect(response)}")
      end
    end)
  end

  test "Rackla.collect - multiple deterministic responses (full: false)" do
    urls = [
      "http://localhost:#{@test_router_port}/api/json/foo-bar",
      "http://localhost:#{@test_router_port}/api/text/foo-bar"
    ]

    [response_1, response_2] =
      urls
      |> request
      |> collect

    assert response_1 == "{\"foo\":\"bar\"}"
    assert response_2 == "foo-bar"
  end

  test "Rackla.collect - multiple deterministic responses (full: true)" do
    urls = [
      "http://localhost:#{@test_router_port}/api/json/foo-bar",
      "http://localhost:#{@test_router_port}/api/text/foo-bar"
    ]

    [response_1, response_2] =
      urls
      |> request(full: true)
      |> collect

    assert response_1.body == "{\"foo\":\"bar\"}"
    assert response_2.body == "foo-bar"
  end

  test "Rackla.map - single response" do
    response_item =
      "http://localhost:#{@test_router_port}/api/text/foo-bar"
      |> request(full: true)
      |> map(&(&1.body))
      |> collect

    assert is_binary(response_item)
    assert response_item == "foo-bar"
  end

  test "Rackla.map - mulitple responses" do
    urls = [
      "http://localhost:#{@test_router_port}/api/text/foo-bar",
      "http://localhost:#{@test_router_port}/api/text/foo-bar",
      "http://localhost:#{@test_router_port}/api/text/foo-bar"
    ]

    expected_response =
      Stream.repeatedly(fn -> "foo-bar" end)
      |> Stream.take(3)
      |> Enum.to_list

    response_item =
      urls
      |> request(full: true)
      |> map(&(&1.body))
      |> collect

    assert is_list(response_item)
    assert response_item == expected_response
  end

  test "Rackla.flat_map - single resuorce" do
    response_item =
      "http://localhost:#{@test_router_port}/api/json/foo-bar"
      |> request
      |> flat_map(fn(_) ->
        request("http://localhost:#{@test_router_port}/api/text/foo-bar", full: true)
      end)
      |> map(&(&1.body))
      |> collect

    assert is_binary(response_item)
    assert response_item == "foo-bar"
  end

  test "Rackla.flat_map - deep nesting" do
    url_1 = "http://localhost:#{@test_router_port}/api/json/foo-bar"
    url_2 = "http://localhost:#{@test_router_port}/api/text/foo-bar"

    response_item =
      url_1
      |> request
      |> flat_map(fn(_) ->
        request([url_1, url_1])
        |> flat_map(fn(_) ->
          request([url_2, url_2, url_2], full: true)
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
    url = "http://localhost:#{@test_router_port}/api/text/foo-bar"

    reduce_function =
      fn(x, acc) ->
        String.upcase(x) <> acc
      end

    response_item =
      [url, url, url]
      |> request
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
    url = "http://localhost:#{@test_router_port}/api/text/foo-bar"

    reduce_function =
      fn(x, acc) ->
        String.upcase(x) <> acc
      end

    accumulator = ""

    response_item =
      [url, url, url]
      |> request
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
      "http://localhost:#{@test_router_port}/api/text/foo-bar",
      "invalid-url"
    ]

    [response_1, response_2] =
      urls
      |> request(full: true)
      |> collect

    case response_1 do
      %Rackla.Response{status: status, headers: headers, body: body} ->
        assert status == 200
        assert body == "foo-bar"
        assert is_map(headers)
      _ -> flunk("Expected Rackla.Response, got: #{inspect(response_1)}")
    end

    assert response_2 == {:error, :nxdomain}
  end

  test "Rackla.map - valid and invalid URL" do
    urls = [
      "http://localhost:#{@test_router_port}/api/text/foo-bar",
      "invalid-url"
    ]

    [response_1, response_2] =
      urls
      |> request(full: true)
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

  test "Rackla.map - nested Rackla type should not be unpacked" do
    expected = "hello"

    rackla =
      "discard this"
      |> just
      |> map(fn(_) ->
        just(expected)
      end)
      |> collect

    case rackla do
      %Rackla{} = nested_rackla ->
        assert collect(nested_rackla) == expected
      _ -> flunk "Expected Rackla type, got: #{rackla}"
    end
  end

  test "Rackla.flat_map - valid and invalid URL (variation 1)" do
    urls = [
      "http://localhost:#{@test_router_port}/api/text/foo-bar",
      "invalid-url"
    ]

    [response_1, response_2] =
      just("test")
      |> flat_map(fn(_) ->
        request(urls, full: true)
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
      "http://localhost:#{@test_router_port}/api/text/foo-bar",
      "invalid-url"
    ]

    [response_1, response_2] =
      just("test")
      |> flat_map(fn(_) ->
        request(urls, full: true)
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
    capture_io(:user, fn ->
      Process.flag(:trap_exit, true)

      Task.start_link(fn ->
        just("test")
        |> map(fn(_) -> raise "oops" end)
        |> collect
      end)

      assert_receive {:EXIT, _pid, {%RuntimeError{message: "oops"}, _rest}}, 5_000
      Logger.flush()
    end)
  end

  test "Rackla.flat_map - wrong return type" do
    capture_io(:user, fn ->
      Process.flag(:trap_exit, true)

      Task.start_link(fn ->
        just("test")
        |> flat_map(fn(_) -> "not a Rackla struct" end)
        |> collect
      end)

      assert_receive {:EXIT, _pid, {{:badmatch, _msg}, _rest}}, 1_000
      Logger.flush()
    end)
  end

  test "Rackla.flat_map - raising exceptions" do
    capture_io(:user, fn ->
      Process.flag(:trap_exit, true)

      Task.start_link(fn ->
        just("test")
        |> flat_map(fn(_) -> raise "oops" end)
        |> collect
      end)

      assert_receive {:EXIT, _pid, {%RuntimeError{message: "oops"}, _rest}}, 5_000
      Logger.flush()
    end)
  end

  test "Timeout - receive_timeout is too short" do
    response =
      "http://localhost:#{@test_router_port}/api/timeout"
      |> request(receive_timeout: 1_000)
      |> collect

    assert response == {:error, :timeout}
  end

  test "Timeout - receive_timeout is long enough" do
    response =
      "http://localhost:#{@test_router_port}/api/timeout"
      |> request(receive_timeout: 2_500)
      |> collect

    assert response == "ok"
  end

  test "Request specific timeout - receive_timeout is too short" do
    response =
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/api/timeout",
        options: %{receive_timeout: 1_000}
      }
      |> request(receive_timeout: 5_000)
      |> collect

    assert response == {:error, :timeout}
  end

  test "Request specific timeout - receive_timeout is long enough" do
    response =
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/api/timeout",
        options: %{receive_timeout: 2_500}
      }
      |> request(receive_timeout: 1)
      |> collect

    assert response == "ok"
  end
  
  test "Follow redirect - do not follow by default" do
    response = 
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/test/redirect/1",
      }
      |> request
      |> collect
      
    assert response == "redirect body"
  end
  
  test "Follow redirect - follow redirect can be enabled in global setting" do
    response = 
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/test/redirect/1",
      }
      |> request(follow_redirect: true)
      |> collect
      
    assert response == "redirect done!"
  end
  
  test "Follow redirect - follow redirect can be enabled in request setting" do
    response = 
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/test/redirect/1",
        options: %{follow_redirect: true}
      }
      |> request
      |> collect
      
    assert response == "redirect done!"
  end
  
  test "Max redirect - default should be 5" do
    response = 
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/test/redirect/5",
      }
      |> request(follow_redirect: true)
      |> collect
      
    assert response == "redirect done!"
    
    response = 
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/test/redirect/6",
      }
      |> request(follow_redirect: true)
      |> collect
      
    assert response == {:error, :max_redirect_overflow}
  end
  
  test "Max redirect - change number of redirects in global setting" do
    response = 
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/test/redirect/10",
      }
      |> request(follow_redirect: true, max_redirect: 10)
      |> collect
      
    assert response == "redirect done!"
  end
  
  test "Max redirect - change number of redirects in request setting" do
    response = 
      %Rackla.Request{
        url: "http://localhost:#{@test_router_port}/test/redirect/10",
        options: %{follow_redirect: true, max_redirect: 10}
      }
      |> request
      |> collect
      
    assert response == "redirect done!"
  end
  
  test "POST redirect - POST are not following redirect by default" do
    response = 
      %Rackla.Request{
        method: :post,
        url: "http://localhost:#{@test_router_port}/test/post-redirect/5",
      }
      |> request(follow_redirect: true)
      |> collect
      
    assert response == {:error, :force_redirect_disabled}
  end
  
  test "POST redirect - POST can be forced to follow redirects in global setting" do
    response = 
      %Rackla.Request{
        method: :post,
        url: "http://localhost:#{@test_router_port}/test/post-redirect/5",
      }
      |> request(follow_redirect: true, force_redirect: true)
      |> collect
      
    assert response == "post redirect done!"
  end
  
  test "POST redirect - POST can be forced to follow redirects in request setting" do
    response = 
      %Rackla.Request{
        method: :post,
        url: "http://localhost:#{@test_router_port}/test/post-redirect/5",
        options: %{follow_redirect: true, force_redirect: true}
      }
      |> request
      |> collect
      
    assert response == "post redirect done!"
  end
  
  test "Convert incoming request to a Rackla.Request" do
    body = "this is a test body"
    url = "http://localhost:#{@test_router_port}/test/incoming_request_with_options"
    
    response =
      %Rackla.Request{
        method: :post,
        url: url,
        headers: %{"test-header" => "test-value"},
        body: body
      }
      |> request
      |> collect
      |> Poison.decode!
      
    assert Map.get(response, "body") == body
    assert Map.get(response, "method") == "post"
    assert Map.get(response, "options") == %{"connect_timeout" => 1337}
    assert Map.get(response, "url") == url
    assert response |> Map.get("headers") |> Map.get("test-header") == "test-value"
  end
  
  test "Convert incoming request with complex url to a Rackla.Request" do
    username_password = "user:password"
    scheme = "http://"
    url = "#{scheme}localhost:#{@test_router_port}/test/incoming_request?key1=value1&key2=value2"
    url_with_authorization = url |> String.split(scheme) |> Enum.join("#{scheme}#{username_password}@")
    
    response =
      %Rackla.Request{
        method: :get,
        url: url_with_authorization
      }
      |> request
      |> collect
      |> Poison.decode!
      
    assert Map.get(response, "method") == "get"
    assert Map.get(response, "url") == url
    assert response |> Map.get("headers") |> Map.get("authorization") == "Basic #{Base.encode64(username_password)}"
  end
end