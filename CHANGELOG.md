# Changelog for Rackla

## 1.1
 - Added Rackla.Proxy to support SOCKS5 and HTTP tunnel proxies.
 - Added option :max_redirect to set the number of redirects.
 - Added option :force_redirect to force redirect (e.g. POST).
 - Removed compiler warnings caused by Elixir 1.3.
 - Removed compiler warnings from tests.
 - Updated all dependencies.

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