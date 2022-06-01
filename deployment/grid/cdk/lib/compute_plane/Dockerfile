ARG HTCGRID_ACCOUNT
ARG HTCGRID_REGION
FROM ${HTCGRID_ACCOUNT}.dkr.ecr.${HTCGRID_REGION}.amazonaws.com/ecr-public/sam/build-python3.7
RUN mkdir -p /asset-temp
RUN mkdir -p /asset-input
WORKDIR /asset-input
COPY dist  /asset-input/dist
COPY source  /asset-input/source
RUN ls -al

RUN pip install --no-cache /asset-input/dist/python/api-0.1-py3-none-any.whl -t /asset-temp
RUN pip install  /asset-input/dist/python/utils-0.1-py3-none-any.whl  -t /asset-temp

WORKDIR /asset-input/source/compute_plane/python/lambda/scaling_metrics
RUN pip install  -r requirements.txt -t /asset-temp
