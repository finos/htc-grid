ARG HTCGRID_ECR_REPO
FROM ${HTCGRID_ECR_REPO}/ecr-public/amazonlinux/amazonlinux:2

# Run as user nobody:nobody
ARG USER=99 #nobody
ARG GROUP=99 #nobody
ARG HOME=/download-layer

RUN yum update -y && \
    yum install -y \
      unzip && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    mkdir -p /tmp/aws-cli/

WORKDIR /tmp/aws-cli
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -fr /tmp/aws-cli/aws* && \
    mkdir -p /download-layer /attach-layer && \
    chown -R $USER:$GROUP /download-layer /attach-layer

USER ${USER}:${GROUP}

ENV REGION=${REGION:-eu-west-1}
ENV LAYER_NAME=lambda
ENV LAYER_VERSION=1
ENV LAYER_ROOT=./
ENV HOME=${HOME:-/download-layer}

WORKDIR ${HOME}
COPY ./download-layer.sh .

CMD ["./download-layer.sh", "-l", "${LAYER_NAME}", "-v", "${LAYER_VERSION}", "-r", "${REGION}", "-d", "${LAYER_ROOT}"]
