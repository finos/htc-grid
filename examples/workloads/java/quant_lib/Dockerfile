# // ARG HTCGRID_ACCOUNT
# // ARG HTCGRID_REGION
# // FROM ${HTCGRID_ACCOUNT}.dkr.ecr.${HTCGRID_REGION}.amazonaws.com/ecr-public/lambda/java:17
FROM public.ecr.aws/lambda/java:17


# //# Copy function code and runtime dependencies from Maven layout
COPY target/classes ${LAMBDA_TASK_ROOT}
COPY target/dependency/* ${LAMBDA_TASK_ROOT}/lib/
COPY ql/QuantLib.jar ${LAMBDA_TASK_ROOT}/lib/QuantLib.jar
COPY ql/libQuantLibJNI.so ${LAMBDA_TASK_ROOT}/lib/libQuantLibJNI.so
COPY ql/libQuantLib.so.0 ${LAMBDA_TASK_ROOT}/lib/libQuantLib.so.0

# // Set the CMD to your handler (could also be done as a parameter override outside of the Dockerfile)
CMD [ "com.htcgrid.quantlib.Bonds::handleRequest" ]


