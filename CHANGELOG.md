# Changelog for Rackla
## 1.2.0
 - Rackla can now be included as a proper library application in production builds.
 - Code base has been split:
  - Rackla: https://github.com/AntonFagerberg/rackla (Rackla code used to build the library).
  - Rackla skeleton: https://github.com/AntonFagerberg/rackla_skeleton (skeleton implementation using Rackla as a library).
 - Thanks again beno!

## 1.1.0
 - Added Rackla.Proxy to support SOCKS5 and HTTP tunnel proxies.
 - Added option :max_redirect to set the number of redirects.
 - Added option :force_redirect to force redirect (e.g. POST).
 - Added incoming_request to convert an incoming Plug request to a Rackla.Request.
 - Removed compiler warnings caused by Elixir 1.3.
 - Removed compiler warnings from tests.
 - Updated all dependencies.
 - Thanks JustMikey & beno!

## 1.0.1
 - Added option to follow redirect. Thanks bAmpT!
 - Updated all dependencies.

## 1.0.0
 - Version bumped to 1.0.0 since the code has been stable for a long time.
 - Since the `Dict` module is going to be deprecated in Elixir, Rackla will now strictly use `Keyword` and `Map`.
 - Using `remix` for automatic reloading recompiling. Thanks @pap and @alanpeabody!
 - Added `dialyxir` to make easier use of dialyzer during development.
 - Fixed a couple of type annotations.
 - Updated all dependencies.

## 0.1.0
 - First public full featured release.