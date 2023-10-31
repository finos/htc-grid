ARG HTCGRID_ECR_REPO
FROM ${HTCGRID_ECR_REPO}

# Run as user nobody:nobody
ARG USER=99 #nobody
ARG GROUP=99 #nobody

ARG HTCGRID_LAMBDA_ENTRYPOINT=lambda_entry_point.sh
COPY ${HTCGRID_LAMBDA_ENTRYPOINT} /lambda_entrypoint_signal.sh

RUN yum update -y && \
    yum install -y \
      procps && \
    yum clean all && \
    rm -rf /var/cache/yum && \
    chmod 755 /lambda_entrypoint_signal.sh

USER ${USER}:${GROUP}

ENTRYPOINT ["/lambda_entrypoint_signal.sh"]
