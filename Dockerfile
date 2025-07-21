FROM node:8.16.2 as node-builder

WORKDIR /app
COPY . .

WORKDIR /app/coordinator/management
RUN npm install && npm run build-css && npm run build

WORKDIR /app/client
RUN npm install && npm run build

FROM hexpm/elixir:1.10.4-erlang-23.0.2-ubuntu-bionic-20200921 as elixir-builder

RUN apt-get update && apt-get install -y \
    git \
    make \
    gcc \
    libc-dev \
    zlib1g-dev \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config

RUN mix local.hex --force
RUN mix local.rebar --force

WORKDIR /app
COPY . .

WORKDIR /app/coordinator
RUN MIX_ENV=prod mix deps.get && \
    MIX_ENV=prod mix release

WORKDIR /app/generator
RUN MIX_ENV=prod mix deps.get && \
    MIX_ENV=prod mix release

COPY --from=node-builder /app/coordinator/priv /app/coordinator/_build/prod/rel/coordinator/lib/coordinator-0.1.0/priv

EXPOSE 8000 9696

CMD ["bash"]
