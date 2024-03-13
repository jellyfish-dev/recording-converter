# Builder image
FROM ubuntu:mantic-20231011 as builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG USERNAME=compositor
ARG RUST_VERSION=1.74

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y -qq && \
  apt-get install -y \
  build-essential curl pkg-config libssl-dev libclang-dev git sudo \
  libegl1-mesa-dev libgl1-mesa-dri libxcb-xfixes0-dev mesa-vulkan-drivers \
  ffmpeg libavcodec-dev libavformat-dev libavfilter-dev libavdevice-dev libopus-dev && \
  rm -rf /var/lib/apt/lists/*

RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
RUN source ~/.cargo/env && rustup install $RUST_VERSION && rustup default $RUST_VERSION

COPY . /root/project
WORKDIR /root/project

RUN source ~/.cargo/env && cargo build --release --no-default-features

FROM membraneframeworklabs/docker_membrane AS build_elixir

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  npm \
  git \
  python3 \
  make \
  cmake \
  libssl-dev \
  libsrtp2-dev \
  ffmpeg \
  clang-format \
  libopus-dev \
  pkgconf

WORKDIR /app

RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
COPY lib lib

RUN mix deps.get
RUN mix setup
RUN mix deps.compile

# compile and build release
RUN mix do compile, release

# Runtime image
FROM ubuntu:mantic-20231011

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_DRIVER_CAPABILITIES=compute,graphics,utility

RUN apt-get update -y -qq && \
  apt-get install -y \
  sudo adduser ffmpeg && \
  rm -rf /var/lib/apt/lists/*

ENV LIVE_COMPOSITOR_WEB_RENDERER_ENABLE=0
ENV LIVE_COMPOSITOR_WEB_RENDERER_GPU_ENABLE=0

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  openssl \
  libncurses5-dev \
  libncursesw5-dev \
  libsrtp2-dev \
  ffmpeg \
  clang-format \
  curl \
  wget \
  build-essential

RUN cd /tmp/ \
  && wget https://downloads.sourceforge.net/opencore-amr/fdk-aac-2.0.0.tar.gz \
  && tar -xf fdk-aac-2.0.0.tar.gz && cd fdk-aac-2.0.0 \
  && ./configure --prefix=/usr --disable-static \
  && make && make install \
  && cd / \
  && rm -rf /tmp/*

RUN apt remove build-essential -y \
  wget \
  && apt autoremove -y


WORKDIR /app

COPY --from=build_elixir /app/_build/prod/rel/recording_converter ./

CMD ["bin/recording_converter", "start"]
