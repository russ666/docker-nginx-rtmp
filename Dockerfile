ARG NGINX_VERSION=1.18.0
ARG NGINX_RTMP_VERSION=1.2.1
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
  rtmpdump \
  nvidia-driver-450 \
  ffmpeg

COPY --from=build-nginx /usr/local/nginx /usr/local/nginx
COPY --from=build-nginx /etc/nginx /etc/nginx

ENV PATH "${PATH}:/usr/local/nginx/sbin"
ADD nginx.conf /etc/nginx/nginx.conf.template
RUN mkdir -p /opt/data && mkdir /www
ADD static /www/static

EXPOSE 1935
EXPOSE 80

CMD envsubst "$(env | sed -e 's/=.*//' -e 's/^/\$/g')" < \
  /etc/nginx/nginx.conf.template > /etc/nginx/nginx.conf && \
  nginx
