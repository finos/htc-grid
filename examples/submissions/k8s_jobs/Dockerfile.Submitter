FROM python:3.7.7-slim-buster

RUN mkdir -p /app/py_connector
RUN mkdir -p /dist

COPY ./dist/* /dist/
COPY ./examples/client/python/requirements.txt /app/py_connector/

WORKDIR /app/py_connector

RUN pip install -r requirements.txt

COPY ./examples/client/python/client.py .
COPY ./examples/client/python/simple_client.py .
COPY ./examples/client/python/portfolio_pricing_client.py .
COPY ./examples/client/python/sample_portfolio.json .



