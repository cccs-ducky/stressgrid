FROM hexpm/elixir:1.17.1-erlang-27.0-ubuntu-noble-20240605 as elixir-builder

RUN apt-get update && apt-get install -y \
    git \
    nodejs \
    npm \
    make \
    gcc \
    libc-dev \
    zlib1g-dev \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config

RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app
COPY . .

WORKDIR /app/coordinator/assets
RUN npm install

WORKDIR /app/coordinator
RUN MIX_ENV=prod mix deps.get --only prod && \
    MIX_ENV=prod mix compile && \
    MIX_ENV=prod mix assets.deploy && \
    MIX_ENV=prod mix release

WORKDIR /app/generator
RUN MIX_ENV=prod mix deps.get --only prod && \
    MIX_ENV=prod mix compile && \
    MIX_ENV=prod mix release

EXPOSE 4000 9696

CMD ["/app/coordinator/_build/prod/rel/coordinator/bin/coordinator", "start"]
