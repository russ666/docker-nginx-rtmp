ARG NGINX_VERSION=1.18.0
ARG NGINX_RTMP_VERSION=1.2.1
ARG FFMPEG_VERSION=4.3.1
ARG NV_CODEC_HEADERS_VERSION=11.0.10.0
ARG NVIDIA_DRIVER_CAPABILITIES=compute,utility,video


##############################
# Build the NGINX-build image.
FROM nvidia/cuda:11.1-devel as build-nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION

# Build dependencies.
RUN apt update && \
  DEBIAN_FRONTEND=noninteractive \
  apt install --no-install-recommends --no-install-suggests -y \
  ca-certificates \
  curl \
  gcc \
  libc-dev \
  make \
  musl-dev \
  openssl \
  libssl-dev \
  libpcre3 \
  libpcre3-dev \
  pkg-config \
  zlib1g-dev \
  wget

# Get nginx source.
RUN cd /tmp && \
  wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

# Get nginx-rtmp module.
RUN cd /tmp && \
  wget https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf v${NGINX_RTMP_VERSION}.tar.gz && rm v${NGINX_RTMP_VERSION}.tar.gz

# Compile nginx with nginx-rtmp module.
RUN cd /tmp/nginx-${NGINX_VERSION} && \
  ./configure \
  --prefix=/usr/local/nginx \
  --add-module=/tmp/nginx-rtmp-module-${NGINX_RTMP_VERSION} \
  --conf-path=/etc/nginx/nginx.conf \
  --with-threads \
  --with-file-aio \
  --with-http_ssl_module \
  --with-debug \
  --with-cc-opt="-Wimplicit-fallthrough=0" && \
  cd /tmp/nginx-${NGINX_VERSION} && make && make install

###############################
# Build the FFmpeg-build image.
FROM nvidia/cuda:11.1-devel as build-ffmpeg
ARG FFMPEG_VERSION
ARG NV_CODEC_HEADERS_VERSION
ARG NVIDIA_DRIVER_CAPABILITIES
ARG PREFIX=/usr/local
ARG MAKEFLAGS="-j4"

# FFmpeg build dependencies.
RUN apt update && \
  DEBIAN_FRONTEND=noninteractive \
  apt install --no-install-recommends --no-install-suggests -y \
  coreutils \
  libmp3lame-dev \
  libfreetype6-dev \
  libfdk-aac-dev \
  libxvidcore-dev \
  libv4l-dev \
  libogg-dev \
  libass-dev \
  libvpx-dev \
  libvorbis-dev \
  libwebp-dev \
  libtheora-dev \
  libssl-dev \
  libopus-dev \
  librtmp-dev \
  libx264-dev \
  libx265-dev \
  pkg-config \
  wget \
  yasm

# Installing Nvidia codec headers
# The NVIDIA headers were moved out of the FFmpeg codebase to a standalone repository in commit 27cbbbb.
# From the commit message:
# External headers are no longer welcome in the ffmpeg codebase because they increase the maintenance burden.
# However, in the NVidia case the vanilla headers need some modifications to be usable in ffmpeg
# therefore we still provide them, but in a separate repository.
RUN cd /tmp \
  && wget https://github.com/FFmpeg/nv-codec-headers/releases/download/n${NV_CODEC_HEADERS_VERSION}/nv-codec-headers-${NV_CODEC_HEADERS_VERSION}.tar.gz \
  && tar zxf nv-codec-headers-${NV_CODEC_HEADERS_VERSION}.tar.gz \
  && cd nv-codec-headers-${NV_CODEC_HEADERS_VERSION} \
  && make install

# Get FFmpeg source.
RUN cd /tmp/ && \
  wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

# Compile ffmpeg.
RUN cd /tmp/ffmpeg-${FFMPEG_VERSION} && \
  ./configure \
    --prefix=${PREFIX} \
    --enable-version3 \
    --enable-gpl \
    --enable-nonfree \
    --enable-small \
    --enable-libmp3lame \
    --enable-libx264 \
    --enable-libx265 \
    --enable-libvpx \
    --enable-libtheora \
    --enable-libvorbis \
    --enable-libopus \
    --enable-libfdk-aac \
    --enable-libass \
    --enable-libwebp \
    --enable-librtmp \
    --enable-postproc \
    --enable-avresample \
    --enable-libfreetype \
    --enable-avfilter \
    --enable-libxvid \
    --enable-libv4l2 \
    --enable-pic \
    --enable-shared \
    --enable-pthreads \
    --enable-shared \
    --enable-nvenc \
    --enable-cuda \
    --enable-cuvid \
    --enable-libnpp \
    --enable-openssl \
    --disable-debug \
    --disable-doc \
    --disable-ffplay \
    --disable-stripping \
    --disable-static \
    --disable-debug \
    --extra-cflags=-I/usr/local/cuda/include \
    --extra-ldflags=-L/usr/local/cuda/lib64 \
    --extra-libs="-lpthread -lm" && \
  make && make install && make distclean

# Cleanup.
RUN rm -rf /var/cache/* /tmp/*

##########################
# Build the release image.
FROM nvidia/cuda:11.1-runtime
ARG NV_CODEC_HEADERS_VERSION
ARG NVIDIA_DRIVER_CAPABILITIES

# Set default ports.
ENV HTTP_PORT 80
ENV HTTPS_PORT 443
ENV RTMP_PORT 1935

RUN apt update && \
  DEBIAN_FRONTEND=noninteractive \
  apt install --no-install-recommends --no-install-suggests -y \
  ca-certificates \
  gettext \
  openssl \
  libpcre3 \
  lame \
  libogg0 \
  curl \
  libass9 \
  libvpx6 \
  libvorbis0a \
  libwebp6 \
  libtheora-bin \
  libopus0 \
  libfdk-aac-dev \
  rtmpdump \
  libx264-dev \
  libx265-dev

COPY --from=build-nginx /usr/local/nginx /usr/local/nginx
COPY --from=build-nginx /etc/nginx /etc/nginx
COPY --from=build-ffmpeg /usr/local /usr/local

# Add NGINX path, config and static files.
ENV PATH "${PATH}:/usr/local/nginx/sbin"
ADD nginx.conf /etc/nginx/nginx.conf.template
RUN mkdir -p /opt/data && mkdir /www
ADD static /www/static

EXPOSE 1935
EXPOSE 80

CMD envsubst "$(env | sed -e 's/=.*//' -e 's/^/\$/g')" < \
  /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && \
  nginx
