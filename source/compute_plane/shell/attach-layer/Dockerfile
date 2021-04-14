FROM amazonlinux:2
RUN mkdir -p /aws-cli/
RUN yum install -y unzip
WORKDIR /aws-cli
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && unzip awscliv2.zip && ./aws/install && mkdir -p /download-layer/ && mkdir -p /attach-layer
WORKDIR /download-layer
ENV REGION eu-west-1
ENV LAYER_NAME lambda
ENV LAYER_VERSION 1
ENV LAYER_ROOT .
COPY ./download-layer.sh .
CMD  ./download-layer.sh -l ${LAYER_NAME} -v ${LAYER_VERSION} -r ${REGION} -d ${LAYER_ROOT}