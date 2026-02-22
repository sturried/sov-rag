FROM elixir:1.15-alpine

RUN apk add --no-cache build-base
WORKDIR /app
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs ./
RUN mix deps.get

COPY . .
RUN mix compile
EXPOSE 4000
CMD ["iex", "-S", "mix"]