ARG NGINX_VERSION=1.18.0
ARG NGINX_RTMP_VERSION=1.2.1
ARG FFMPEG_VERSION=4.3.1
ARG NV_CODEC_HEADERS_VERSION=10.0.26.1
ARG NVIDIA_VISIBLE_DEVICES=all
ARG NVIDIA_DRIVER_CAPABILITIES=compute,utility,video

FROM buildpack-deps:stretch as build-nginx
ARG NGINX_VERSION
ARG NGINX_RTMP_VERSION

RUN apt update && \
  DEBIAN_FRONTEND=noninteractive \
  apt install --no-install-recommends --no-install-suggests -y \
  ca-certificates \
  openssl \
  libssl-dev \
  libpcre3-dev

RUN cd /tmp && \
  wget https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz && \
  tar zxf nginx-${NGINX_VERSION}.tar.gz && \
  rm nginx-${NGINX_VERSION}.tar.gz

RUN cd /tmp && \
  wget https://github.com/arut/nginx-rtmp-module/archive/v${NGINX_RTMP_VERSION}.tar.gz && \
  tar zxf v${NGINX_RTMP_VERSION}.tar.gz && rm v${NGINX_RTMP_VERSION}.tar.gz

RUN cd /tmp/nginx-${NGINX_VERSION} && \
  ./configure \
  --prefix=/usr/local/nginx \
  --add-module=/tmp/nginx-rtmp-module-${NGINX_RTMP_VERSION} \
  --conf-path=/etc/nginx/nginx.conf \
  --with-threads \
  --with-http_ssl_module \
  --with-debug \
  --with-ipv6 && \
  cd /tmp/nginx-${NGINX_VERSION} && make && make install

FROM nvidia/cuda:11.1-devel as build-ffmpeg
ARG FFMPEG_VERSION
ARG NV_CODEC_HEADERS_VERSION
ARG NVIDIA_DRIVER_CAPABILITIES
ARG PREFIX=/usr/local
ARG MAKEFLAGS="-j4"

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

RUN cd /tmp \
  && wget https://github.com/FFmpeg/nv-codec-headers/releases/download/n${NV_CODEC_HEADERS_VERSION}/nv-codec-headers-${NV_CODEC_HEADERS_VERSION}.tar.gz \
  && tar zxf nv-codec-headers-${NV_CODEC_HEADERS_VERSION}.tar.gz \
  && cd nv-codec-headers-${NV_CODEC_HEADERS_VERSION} \
  && make install

RUN cd /tmp/ && \
  wget http://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.gz && \
  tar zxf ffmpeg-${FFMPEG_VERSION}.tar.gz && rm ffmpeg-${FFMPEG_VERSION}.tar.gz

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

RUN rm -rf /var/cache/* /tmp/*


FROM nvidia/cuda:11.1-runtime
ARG NVIDIA_VISIBLE_DEVICES
ARG NVIDIA_DRIVER_CAPABILITIES

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
  curl \
  lame \
  libogg0 \
  libv4l-0 \
  libass9 \
  libvpx6 \
  libvorbis0a \
  libwebp6 \
  libwebpmux3 \
  libxvidcore4 \
  libtheora-bin \
  libopus0 \
  libfdk-aac-dev \
  libx264-dev \
  libx265-dev \
  rtmpdump \
  nvidia-driver-450

COPY --from=build-nginx /usr/local/nginx /usr/local/nginx
COPY --from=build-nginx /etc/nginx /etc/nginx
COPY --from=build-ffmpeg /usr/local/lib /usr/local/lib
COPY --from=build-ffmpeg /usr/local/bin /usr/local/bin

ENV PATH "${PATH}:/usr/local/nginx/sbin"
ADD nginx.conf /etc/nginx/nginx.conf.template
RUN mkdir -p /opt/data && mkdir /www
ADD static /www/static

EXPOSE 80
EXPOSE 1935

CMD envsubst "$(env | sed -e 's/=.*//' -e 's/^/\$/g')" < \
  /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && \
  nginx
