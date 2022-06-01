ARG HTCGRID_ACCOUNT
ARG HTCGRID_REGION
FROM ${HTCGRID_ACCOUNT}.dkr.ecr.${HTCGRID_REGION}.amazonaws.com/ecr-public/sam/build-python3.7
RUN mkdir -p /asset-temp
RUN mkdir -p /asset-input
WORKDIR /asset-input
COPY dist  /asset-input/dist
COPY source  /asset-input/source
RUN ls -al



WORKDIR /asset-input/source/control_plane/python/lambda/submit_tasks
RUN pip install --no-cache -r requirements.txt -t /asset-temp

WORKDIR /asset-input/source/control_plane/python/lambda/get_results
RUN pip install  -r requirements.txt -t /asset-temp

WORKDIR /asset-input/source/control_plane/python/lambda/cancel_tasks
RUN pip install  -r requirements.txt -t /asset-temp

WORKDIR /asset-input/source/control_plane/python/lambda/ttl_checker
RUN pip install  -r requirements.txt -t /asset-temp