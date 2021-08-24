FROM public.ecr.aws/lambda/dotnet:5.0
COPY lambda_entry_point.sh  /lambda_entrypoint_signal.sh
ENTRYPOINT ["/lambda_entrypoint_signal.sh"]