ARG HTCGRID_ECR_REPO

FROM ${HTCGRID_ECR_REPO}

COPY lambda_entry_point_provided.sh  /lambda_entrypoint_signal.sh

RUN chmod u+x /lambda_entrypoint_signal.sh && \
    yum update -y && \
    yum install -y procps && \
    yum clean all

ENTRYPOINT ["/lambda_entrypoint_signal.sh"]
