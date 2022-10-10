ARG HTCGRID_ACCOUNT 
ARG HTCGRID_REGION
FROM ${HTCGRID_ACCOUNT}.dkr.ecr.${HTCGRID_REGION}.amazonaws.com/ecr-public/lambda/provided:al2
COPY lambda_entry_point_provided.sh  /lambda_entrypoint_signal.sh
RUN chmod u+x /lambda_entrypoint_signal.sh
ENTRYPOINT ["/lambda_entrypoint_signal.sh"]