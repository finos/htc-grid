FROM public.ecr.aws/lambda/java:17

# Run as user nobody:nobody
ARG USER=99 #nobody
ARG GROUP=99 #nobody

USER ${USER}:${GROUP}

# Copy function code and runtime dependencies from Maven layout
COPY target/classes ${LAMBDA_TASK_ROOT}
COPY target/dependency/* ${LAMBDA_TASK_ROOT}/lib/

# Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "com.htcgrid.examples.MockComputeEngine::handleRequest" ]
