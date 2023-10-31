FROM golang:alpine

# Run as user nobody:nobody
ARG USER=65534 #nobody
ARG GROUP=65534 #nogroup
ARG HUGO_VERSION=0.74.3

WORKDIR /tmp
RUN apk --no-cache --update add \
        git \
        gcc \
        musl-dev \
        g++ \
        wget && \
    wget https://github.com/gohugoio/hugo/releases/download/v${HUGO_VERSION}/hugo_${HUGO_VERSION}_Linux-64bit.tar.gz && \
    tar -xf hugo_${HUGO_VERSION}_Linux-64bit.tar.gz hugo && \
    rm -rf hugo_${HUGO_VERSION}_Linux-64bit.tar.gz && \
    cp hugo /usr/bin/hugo

USER ${USER}:${GROUP}

WORKDIR /www
RUN git clone https://github.com/matcornic/hugo-theme-learn/ themes/learn
COPY . /www/

ENTRYPOINT ["hugo", "server", "--bind", "0.0.0.0"]
CMD [""]