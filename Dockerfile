# Builder image
FROM ubuntu:mantic-20231011 as builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG USERNAME=compositor
ARG RUST_VERSION=1.74

ENV DEBIAN_FRONTEND=noninteractive
# Set locale to UTF-8
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

RUN apt-get update -y -qq && \
  apt-get install -y \
  build-essential curl pkg-config libssl-dev libclang-dev git sudo \
  libegl1-mesa-dev libgl1-mesa-dri libxcb-xfixes0-dev mesa-vulkan-drivers \
  ffmpeg libavcodec-dev libavformat-dev libavfilter-dev libavdevice-dev libopus-dev && \
  rm -rf /var/lib/apt/lists/*

RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
RUN source ~/.cargo/env && rustup install $RUST_VERSION && rustup default $RUST_VERSION

RUN git clone https://github.com/membraneframework/video_compositor.git && cd video_compositor && git checkout 7d0a8be312de17043aebdbcea19b43a3ce1138eb

RUN mv video_compositor /root/project

WORKDIR /root/project

RUN source ~/.cargo/env && cargo build --release --no-default-features

# FROM elixir:1.16.2-otp-25 AS build_elixir
# FROM cimg/elixir:1.16.0-erlang-26.2.1 AS build_elixir
FROM membraneframeworklabs/docker_membrane:latest as build_elixir
# Set locale to UTF-8
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  git \
  python3 \
  make \
  cmake \
  libssl-dev \
  libsrtp2-dev \
  clang-format \
  libopus-dev \
  pkgconf \
  libssl-dev \
  libflac-dev \
  libmad0-dev \
  libopus-dev \
  libsdl2-dev \
  portaudio19-dev \
  libsrtp2-dev \
  libmp3lame-dev \
  libva-dev \
  libvdpau-dev \
  libvorbis-dev \
  libxcb1-dev \
  libxcb-shm0-dev \
  libxcb-xfixes0-dev \
  libx264-dev \
  libfreetype-dev \
  libx265-dev \
  libavutil-dev


WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_DRIVER_CAPABILITIES=compute,graphics,utility
ENV LIVE_COMPOSITOR_WEB_RENDERER_ENABLE=0
ENV LIVE_COMPOSITOR_WEB_RENDERER_GPU_ENABLE=0


RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
COPY lib lib


RUN mix deps.get
RUN mix deps.compile

# compile and build release
RUN mix do compile, release

# Runtime image
FROM ubuntu:mantic-20231011

ENV COMPOSITOR_PATH=/app/compositor/video_compositor

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_DRIVER_CAPABILITIES=compute,graphics,utility

# Set locale to UTF-8
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

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
COPY --from=builder /root/project/target/release compositor

RUN mkdir output


CMD ["bin/recording_converter", "start"]
