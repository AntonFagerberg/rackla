FROM trenpixster/elixir:1.0.4

ADD . /rackla
WORKDIR /rackla

RUN mix deps.get
RUN mix compile

CMD mix server

EXPOSE 4000
