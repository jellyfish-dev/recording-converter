# Builder image
FROM ubuntu:mantic-20231011 as builder

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG USERNAME=compositor
ARG RUST_VERSION=1.74
ARG LIVE_COMPOSITOR_LOGGER_LEVEL="debug,wgpu_hal=warn,wgpu_core=warn,naga=warn"

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

RUN git clone https://github.com/membraneframework/video_compositor.git && cd video_compositor && git checkout 84f8fb8c0d0dbe52e6e449ae66c887804764c6e3

RUN mv video_compositor /root/project

WORKDIR /root/project

RUN source ~/.cargo/env && cargo build --release --no-default-features

FROM ubuntu:mantic-20231011 as build_elixir


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

# Common tools and dependencies, GCC, ASDF
# Note: We setup locales using the snippet from `ubuntu` image readme.
RUN apt-get update \
  && apt-get install -y software-properties-common \
  && add-apt-repository ppa:ubuntu-toolchain-r/test -y \
  && apt-get update \
  && apt-get install -y \
  autoconf \
  automake \
  build-essential \
  cmake \
  clang-format \
  curl \
  gcc-9 \
  git \
  git-core \
  libass-dev \
  libffi-dev \
  libfreetype6-dev \
  libglib2.0-dev \
  libgnutls28-dev \
  libncurses-dev \
  libreadline-dev \
  libssl-dev \
  libtool \
  libxslt-dev \
  libyaml-dev \
  locales \
  meson \
  ninja-build \
  unixodbc-dev \
  texinfo \
  unzip \
  wget \
  yasm \
  zlib1g-dev \
  && rm -rf /var/lib/apt/lists/* \
  && localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8 \
  && git clone https://github.com/asdf-vm/asdf.git /root/.asdf -b v0.8.0

ENV LANG en_US.utf8

# Add ASDF to PATH
# Note: This is essentialy an intersection of what the asdf init script does and what
# we need during container build phase. The init script does check whether these paths
# are present in PATH variable before adding new ones. We are going to fully initialise
# asdf in the entrypoint script.
ENV PATH /root/.asdf/bin:/root/.asdf/shims:$PATH

# Runtime deps
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

# Erlang
RUN apt-get update \
  # This invocation causes `keyboard-configuration` package to be installed,
  # which seems to assume interactivity during Docker build. Setting DEBIAN_FRONTEND
  # helps for this issue, although this is not recommended in general.
  && DEBIAN_FRONTEND=noninteractive apt-get install -y \
  autoconf \
  build-essential \
  && asdf plugin-add erlang https://github.com/asdf-vm/asdf-erlang.git \
  && asdf install erlang 26.0.2 \
  && asdf global erlang 26.0.2 \
  && rm -rf /tmp/*

# Elixir
RUN asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git \
  && asdf install elixir 1.15.5-otp-26 \
  && asdf global elixir 1.15.5-otp-26 \
  && mix local.hex --force \
  && mix local.rebar --force \
  && rm -rf /tmp/*

# Multimedia libraries
RUN apt-get update \
  && apt-get install -y \
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
  && rm -rf /var/lib/apt/lists/* \
  && cd /tmp/ \
  && wget https://downloads.sourceforge.net/opencore-amr/fdk-aac-2.0.0.tar.gz \
  && tar -xf fdk-aac-2.0.0.tar.gz && cd fdk-aac-2.0.0 \
  && ./configure --prefix=/usr --disable-static \
  && make && make install \
  && cd / \
  && rm -rf /tmp/*

# FFmpeg
RUN asdf plugin add ffmpeg \
  && export ASDF_FFMPEG_OPTIONS_EXTRA="--disable-debug \
  --disable-doc \
  --enable-ffplay \
  --enable-fontconfig \
  --enable-gpl \
  --enable-libass \
  --enable-libfdk_aac \
  --enable-libmp3lame \
  --enable-libopus \
  --enable-libx264 \
  --enable-libx265 \
  --enable-libfreetype \
  --enable-libharfbuzz \
  --enable-nonfree \
  --enable-openssl \
  --enable-postproc \
  --enable-shared \
  --enable-small \
  --enable-version3 \
  --extra-libs=-ldl \
  --extra-libs=-lpthread" \
  && asdf install ffmpeg 6.1.1 \
  && asdf global ffmpeg 6.1.1 \
  && cp -r /root/.asdf/installs/ffmpeg/6.1.1/lib/* /usr/lib

WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive
ENV NVIDIA_DRIVER_CAPABILITIES=compute,graphics,utility
ENV LIVE_COMPOSITOR_WEB_RENDERER_ENABLE=0
ENV LIVE_COMPOSITOR_WEB_RENDERER_GPU_ENABLE=0
ARG LIVE_COMPOSITOR_LOGGER_LEVEL="debug,wgpu_hal=warn,wgpu_core=warn,naga=warn"


COPY --from=builder /root/project/target/release compositor
ENV COMPOSITOR_PATH=/app/compositor/video_compositor

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
ARG LIVE_COMPOSITOR_LOGGER_LEVEL="debug,wgpu_hal=warn,wgpu_core=warn,naga=warn"

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
