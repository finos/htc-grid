ARG HTCGRID_ECR_REPO
FROM ${HTCGRID_ECR_REPO}

ARG HTCGRID_LAMBDA_ENTRYPOINT=lambda_entry_point.sh
COPY ${HTCGRID_LAMBDA_ENTRYPOINT} /lambda_entrypoint_signal.sh

RUN chmod u+x /lambda_entrypoint_signal.sh && \
    yum update -y && \
    yum install -y procps && \
    yum clean all && \
    rm -rf /var/cache/yum

ENTRYPOINT ["/lambda_entrypoint_signal.sh"]
