// Scheduler Resources
import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as s3 from "aws-cdk-lib/aws-s3";
import * as iam from "aws-cdk-lib/aws-iam";
import * as elasticache from "aws-cdk-lib/aws-elasticache";
import * as logs from "aws-cdk-lib/aws-logs";
import * as events from "aws-cdk-lib/aws-events";
import * as eventsTargets from "aws-cdk-lib/aws-events-targets";
import * as apigw from "aws-cdk-lib/aws-apigateway";
import * as cognito from "aws-cdk-lib/aws-cognito";
import * as sqs from "aws-cdk-lib/aws-sqs";
import * as dynamodb from "aws-cdk-lib/aws-dynamodb";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as lambdaPy from "@aws-cdk/aws-lambda-python-alpha";
import * as eks from "aws-cdk-lib/aws-eks";
import * as secretsmanager from"aws-cdk-lib/aws-secretsmanager";


interface SchedulerProps extends cdk.StackProps {
    vpc: ec2.IVpc;
    vpc_default_sg: ec2.ISecurityGroup;
    cognito_userpool: cognito.IUserPool;
    eks_cluster: eks.ICluster;
    readonly projectName : string ;
    readonly s3BucketName : string; //=.toLowerCase();
    readonly ddbTableName : string;
    readonly ddbService : string;
    readonly ddbConfig : string;
    readonly ddbDefaultRead: number;
    readonly ddbDefaultWrite: number;
    readonly taskService :string ;
    readonly taskConfig : string;
    readonly sqsQueue: string;
    readonly sqsDlq: string

    readonly metricsAreEnabled: string ;
    readonly metricsSubmitTasksLambdaConnectionString: string ;
    readonly metricsCancelTasksLambdaConnectionString: string;
    readonly metricsGetResultsLambdaConnectionString: string;
    readonly metricsTtlCheckerLambdaConnectionString: string;
    readonly errorLogGroup: string;
    readonly errorLoggingStream: string;
    readonly taskInputPassedViaExternalStorage: number ;
    readonly gridStorageService:string ;
    readonly lambdaNameSubmitTasks:string ;
    readonly lambdaNameCancelTasks: string;
    readonly lambdaNameGetResults: string;
    readonly lambdaNameTtlChecker: string;
}

export class SchedulerStack extends cdk.Stack {
    // Get context values
    private projectName: string;
    private s3BucketName: string;
    private ddbTableName: string;

    private ddbService: string;
    private ddbConfig: string;
    private taskService: string;
    private taskConfig: string;
    private ddbDefaultRead: number;
    private ddbDefaultWrite: number;
    private sqsQueueName: string;
    private sqsDlqName : string;
    private metricsAreEnabled: string;
    private metricsSubmitTasksLambdaConnectionString: string;
    private metricsCancelTasksLambdaConnectionString: string;
    private metricsGetResultsLambdaConnectionString: string;
    private metricsTtlCheckerLambdaConnectionString: string;
    private errorLogGroup: string;
    private errorLoggingStream: string;
    private gridStorageService: string;
    private lambdaNameSubmitTasks: string;
    private lambdaNameSubmitTasksRole: string ;
    private lambdaNameCancelTasks: string;
    private lambdaNameCancelTasksRole: string;
    private lambdaNameGetResults: string;
    private lambdaNameGetResultsRole:string ;
    private lambdaNameTtlChecker: string;
    private lambdaNameTtlCheckerRole: string;
    private taskInputPassedViaExternalStorage: number;
    // Will most likely end up being moved to a prop passed from eks_cluster
    private nlbInfluxdb: string;
    private apiGatewayVersion: string;

    private vpc: ec2.IVpc;
    private vpcDefaultSg: ec2.ISecurityGroup;
    private cognitoUserpool: cognito.IUserPool;
    private lambdaLayers: lambda.LayerVersion[];
    private lambdaStsAssumeRole: iam.PolicyDocument;
    private clusterName: string;

    // resources that will be created
    private taskstatusTable: dynamodb.Table;
    private elasticacheCluster: elasticache.CfnCacheCluster;
    private htcStdoutBucket: s3.Bucket;
    private sqsQueue: sqs.Queue;
    private sqsDlq: sqs.Queue;
    private submitTaskFunction: lambdaPy.PythonFunction;
    private getResultsFunction: lambdaPy.PythonFunction;
    private cancelTasksFunction: lambdaPy.PythonFunction;
    private ttlCheckerFunction: lambdaPy.PythonFunction;

    private submitTaskIntegration: apigw.LambdaIntegration;
    private getResultsIntegration: apigw.LambdaIntegration;
    private cancelTasksIntegration: apigw.LambdaIntegration;

    public apiKeySecret: secretsmanager.ISecret ;
    public apiKey: apigw.IApiKey ;
    public apiGwKey: string;
    public publicApiGwUrl: string;
    public privateApiGwUrl: string;
    public redisUrl: string;

    constructor(scope: Construct, id: string, props: SchedulerProps) {
        super(scope, id, props);

        this.vpc = props.vpc;
        this.vpcDefaultSg = props.vpc_default_sg;
        this.cognitoUserpool = props.cognito_userpool;
        this.clusterName = props.eks_cluster.clusterName;

        this.ddbService=props.ddbService;
        this.ddbConfig=props.ddbConfig;
        this.taskService=props.taskService;
        this.taskConfig=props.taskConfig;
        this.ddbDefaultRead=props.ddbDefaultRead;
        this.ddbDefaultWrite=props.ddbDefaultWrite;
        this.sqsQueueName=props.sqsQueue;
        this.sqsDlqName =props.sqsDlq;
        this.metricsAreEnabled=props.metricsAreEnabled;
        this.metricsSubmitTasksLambdaConnectionString=props.metricsSubmitTasksLambdaConnectionString;
        this.metricsCancelTasksLambdaConnectionString=props.metricsCancelTasksLambdaConnectionString;
        this.metricsGetResultsLambdaConnectionString=props.metricsGetResultsLambdaConnectionString;
        this.metricsTtlCheckerLambdaConnectionString=props.metricsTtlCheckerLambdaConnectionString;
        this.errorLogGroup=props.errorLogGroup;
        this.errorLoggingStream=props.errorLoggingStream
        this.gridStorageService=props.gridStorageService
        this.lambdaNameSubmitTasks=props.lambdaNameSubmitTasks
        this.lambdaNameSubmitTasksRole = `role_lambda_submit_task-${this.projectName}`;
        this.lambdaNameCancelTasks=props.lambdaNameCancelTasks
        this.lambdaNameCancelTasksRole = `role_lambda_cancel_task-${this.projectName}`;
        this.lambdaNameGetResults=props.lambdaNameGetResults
        this.lambdaNameGetResultsRole = `role_lambda_get_results-${this.projectName}`;
        this.lambdaNameTtlChecker=props.lambdaNameTtlChecker
        this.lambdaNameTtlCheckerRole = `role_lambda_ttl_checker-${this.projectName}`;
        this.taskInputPassedViaExternalStorage = props.taskInputPassedViaExternalStorage ;

        this.taskstatusTable = this.createDynamodb();

        this.elasticacheCluster = this.createRedisCluster();

        this.htcStdoutBucket = this.createS3Bucket();

        [this.sqsQueue, this.sqsDlq] = this.createQueues();

        this.lambdaLayers = [
            new lambda.LayerVersion(this, "api_layer", {
                code: lambda.Code.fromAsset("../../../", {
                    bundling: this.get_lambda_bundle("source/client/python/api-v0.1/"),
                    exclude:["**/node_modules","venv","**/.terraform","**/cdk.out"]
                }),
            }),
            // new lambdaPy.PythonLayerVersion(this, 'api_layer', {
            //   entry: '../../../source/client/python/api-v0.1/'
            // }),
            // new lambda.LayerVersion(this, 'utils_layer', {
            //   code: lambda.Code.fromAsset('../../../', {bundling: this.get_lambda_bundle('source/client/python/utils/')})
            // }),
            new lambdaPy.PythonLayerVersion(this, "utils_layer", {
                entry: "../../../source/client/python/utils/",
            }),
        ];
        this.lambdaStsAssumeRole = new iam.PolicyDocument({
            statements: [
                new iam.PolicyStatement({
                    resources: ["*"],
                    actions: ["sts:AssumeRole"],
                    effect: iam.Effect.ALLOW,
                }),
            ],
        });

        this.submitTaskFunction = this.createSubmitLambda();
        this.getResultsFunction = this.createGetLambda();
        this.cancelTasksFunction = this.createCancelLambda();
        this.ttlCheckerFunction = this.createTtlLambda();

        this.enableLambdaLogging();

        this.submitTaskIntegration = new apigw.LambdaIntegration(
            this.submitTaskFunction
        );
        this.getResultsIntegration = new apigw.LambdaIntegration(
            this.getResultsFunction
        );
        this.cancelTasksIntegration = new apigw.LambdaIntegration(
            this.cancelTasksFunction
        );
        const privateApiInfo = this.createPrivateApiGW();
        const publicApiInfo = this.createPublicApiGW();

        this.apiGwKey = privateApiInfo[2];
        this.publicApiGwUrl = publicApiInfo.url;
        this.privateApiGwUrl = privateApiInfo[0].url;
        this.redisUrl = this.elasticacheCluster.attrRedisEndpointAddress;
    }
    private get_lambda_bundle(working_dir: string): cdk.BundlingOptions {
        return {
            image: lambda.Runtime.PYTHON_3_7.bundlingImage,
            command: [
                "bash",
                "-c",
                `cd ${working_dir} && pip install --no-cache -r requirements_layer.txt -t /asset-output && cp -au . /asset-output`,
            ],
        };
    }
    private createDynamodb(): dynamodb.Table {
        const ddb_gsi_ttl_read = this.ddbDefaultRead;
        const ddb_gsi_ttl_write = this.ddbDefaultWrite;
        const ddb_index_read = this.ddbDefaultRead;
        const ddb_index_write = this.ddbDefaultWrite;

        const taskstatusTable = new dynamodb.Table(this, "htc_tasks_status_table", {
            tableName: this.ddbTableName,
            readCapacity: this.ddbDefaultRead,
            writeCapacity: this.ddbDefaultWrite,
            partitionKey: { name: "task_id", type: dynamodb.AttributeType.STRING },
            removalPolicy: cdk.RemovalPolicy.DESTROY,
        });
        cdk.Tags.of(taskstatusTable).add("service", "htc-aws");

        taskstatusTable.addGlobalSecondaryIndex({
            indexName: "gsi_ttl_index",
            partitionKey: {
                name: "task_status",
                type: dynamodb.AttributeType.STRING,
            },
            sortKey: {
                name: "heartbeat_expiration_timestamp",
                type: dynamodb.AttributeType.STRING,
            },
            readCapacity: ddb_gsi_ttl_read,
            writeCapacity: ddb_gsi_ttl_write,
            projectionType: dynamodb.ProjectionType.INCLUDE,
            nonKeyAttributes: ["task_id", "task_owner", "task_priority"],
        });

        taskstatusTable.addGlobalSecondaryIndex({
            indexName: "gsi_session_index",
            partitionKey: { name: "session_id", type: dynamodb.AttributeType.STRING },
            sortKey: { name: "task_status", type: dynamodb.AttributeType.STRING },
            readCapacity: ddb_index_read,
            writeCapacity: ddb_index_write,
            projectionType: dynamodb.ProjectionType.INCLUDE,
            nonKeyAttributes: ["task_id"],
        });
        return taskstatusTable;

        // # attribute {
        // #   name = "submission_timestamp"
        // #   type = "N"
        // # }

        // # attribute {
        // #   name = "task_completion_timestamp"
        // #   type = "N"
        // # }

        // # attribute {
        // #   name = "task_owner"
        // #   type = "S"
        // # }
        // # default value "None"

        // # attribute {
        // #   name = "retries"
        // #   type = "N"
        // # }

        // # attribute {
        // #   name = "task_definition"
        // #   type = "S"
        // # }

        // # attribute {
        // #   name = "sqs_handler_id"
        // #   type = "S"
        // # }

        // # attribute {
        // #   name = "parent_session_id"
        // #   type = "S"
        // # }
    }
    private createRedisCluster(): elasticache.CfnCacheCluster {
        const subnets = this.vpc.privateSubnets;
        const vpc_subnet_ids = [
            ...(function* () {
                for (let subnet of subnets) yield subnet.subnetId;
            })(),
        ];
        const elasticacheSubnetGroup = new elasticache.CfnSubnetGroup(
            this,
            "io_redis_subnet_group",
            {
                description: "htc-grid elasticache subnet group", // required
                subnetIds: vpc_subnet_ids,
                cacheSubnetGroupName: "stdin-stdout-cache-subnet", // stdin-stdout-cache-subnet-${lower(local.suffix)}
            }
        );

        const elasticacheparamGroup = new elasticache.CfnParameterGroup(
            this,
            "cache-config",
            {
                description: "htc-grid elasticache parameter group", // required
                cacheParameterGroupFamily: "redis5.0", // ParameterGroupName not supported yet
                properties: { "maxmemory-policy": "allkeys-lru" },
            }
        );

        const allowincomingRedis = new ec2.SecurityGroup(
            this,
            "allow_incoming_redis",
            {
                securityGroupName: "redis-io-cache", //redis-io-cache-${lower(local.suffix)}
                description: "Allow Redis inbound traffic on port 6379",
                vpc: this.vpc,
                allowAllOutbound: true,
            }
        );
        allowincomingRedis.addIngressRule(
            ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
            ec2.Port.tcp(6379),
            "tcp from VPC"
        );

        const elasticacheCluster = new elasticache.CfnCacheCluster(
            this,
            "stdin_stdout_cache",
            {
                clusterName: "stdin-stdout-cache", // stdin-stdout-cache-${lower(local.suffix)}
                engine: "redis",
                cacheNodeType: "cache.r4.large",
                numCacheNodes: 1,
                engineVersion: "5.0.6",
                port: 6379,
                cacheSubnetGroupName: elasticacheSubnetGroup.cacheSubnetGroupName,
                //cacheSecurityGroupNames:  [allowincomingRedis.securityGroupName],// secgroupids
                cacheParameterGroupName: elasticacheparamGroup.ref,
                vpcSecurityGroupIds: [allowincomingRedis.securityGroupId],
            }
        );

        // CDK *should* take care of mapping this dependencies for us, but adding for terraform:cdk consistency
        elasticacheCluster.addDependsOn(elasticacheSubnetGroup);
        return elasticacheCluster;
        // ------------------------------------------------------------
    }
    private createS3Bucket(): s3.Bucket {
        return new s3.Bucket(this, "htc-stdout-bucket", {
            bucketName: this.s3BucketName,
            accessControl: s3.BucketAccessControl.PRIVATE,
            versioned: true,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
        });
    }
    private createQueues(): [sqs.Queue, sqs.Queue] {
        const priorities = {
            __0: 0,
        };
        const sqsQueue = this.createQueue(
            `${this.sqsQueueName}__0`,
            cdk.Duration.seconds(40),
            cdk.Duration.seconds(1209600)
        );
        Object.keys(priorities).forEach((key) => {
            if (key !== "__0") {
                this.createQueue(
                    `${this.sqsQueueName}${key}`,
                    cdk.Duration.seconds(40),
                    cdk.Duration.seconds(1209600)
                );
            }
        });
        const sqsDlq = this.createQueue(
            this.sqsDlqName,
            undefined,
            cdk.Duration.seconds(1209600)
        );
        return [sqsQueue, sqsDlq];
    }
    private createQueue(
        identifier: string,
        timeout?: cdk.Duration,
        retention?: cdk.Duration
    ): sqs.Queue {
        const queue = new sqs.Queue(this, identifier, {
            queueName: identifier,
            visibilityTimeout: timeout,
            retentionPeriod: retention,
        });
        cdk.Tags.of(queue).add("service", "htc-aws");
        return queue;
    }
    private createSubmitLambda(): lambdaPy.PythonFunction {
        const submit_task_lambda_role = new iam.Role(
            this,
            "submit_task_lambda_role",
            {
                roleName: this.lambdaNameSubmitTasksRole,
                assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
                inlinePolicies: {
                    AssumeRole: this.lambdaStsAssumeRole,
                },
            }
        );
        const submit_task_function = new lambdaPy.PythonFunction(
            this,
            "submit_task_lambda_functions",
            {
                // If requirements.txt exists at entry path, don't need to explicitly state path like terraform
                entry: "../../../source/control_plane/python/lambda/submit_tasks",
                index: "submit_tasks.py",
                handler: "lambda_handler",
                layers: this.lambdaLayers,
                functionName: this.lambdaNameSubmitTasks,
                runtime: lambda.Runtime.PYTHON_3_7,
                memorySize: 1024,
                timeout: cdk.Duration.seconds(300),
                role: submit_task_lambda_role,
                vpcSubnets: this.vpc.selectSubnets({
                    subnetType: ec2.SubnetType.PRIVATE,
                }),
                securityGroups: [this.vpcDefaultSg],
                environment: {
                    STATE_TABLE_NAME: this.taskstatusTable.tableName,
                    STATE_TABLE_SERVICE: this.ddbService,
                    STATE_TABLE_CONFIG: this.ddbConfig,
                    TASKS_QUEUE_NAME: this.sqsQueue.queueName,
                    TASKS_QUEUE_DLQ_NAME: this.sqsDlq.queueName,
                    TASK_QUEUE_SERVICE: this.taskService,
                    TASK_QUEUE_CONFIG: this.taskConfig,
                    METRICS_ARE_ENABLED: this.metricsAreEnabled,
                    METRICS_SUBMIT_TASKS_LAMBDA_CONNECTION_STRING:
                    this.metricsSubmitTasksLambdaConnectionString,
                    ERROR_LOG_GROUP: this.errorLogGroup,
                    ERROR_LOGGING_STREAM: this.errorLoggingStream,
                    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE: `${this.taskInputPassedViaExternalStorage}`,
                    GRID_STORAGE_SERVICE: this.gridStorageService,
                    S3_BUCKET: this.htcStdoutBucket.bucketName,
                    // Need to confirm if below is same as: aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address
                    REDIS_URL: this.elasticacheCluster.attrRedisEndpointAddress,
                    METRICS_GRAFANA_PRIVATE_IP: this.nlbInfluxdb,
                    REGION: this.region,
                },
            }
        );
        cdk.Tags.of(submit_task_function).add("service", "htc-grid");
        return submit_task_function;
    }
    private createGetLambda(): lambdaPy.PythonFunction {
        const get_results_lambda_role = new iam.Role(
            this,
            "get_results_lambda_role",
            {
                roleName: this.lambdaNameGetResultsRole,
                assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
                inlinePolicies: {
                    AssumeRole: this.lambdaStsAssumeRole,
                },
            }
        );
        const get_results_function = new lambdaPy.PythonFunction(
            this,
            "get_results_lambda_functions",
            {
                // If requirements.txt exists at entry path, don't need to explicitly state path like terraform
                entry: "../../../source/control_plane/python/lambda/get_results",
                index: "get_results.py",
                handler: "lambda_handler",
                layers: this.lambdaLayers,
                functionName: this.lambdaNameGetResults,
                runtime: lambda.Runtime.PYTHON_3_7,
                memorySize: 1024,
                timeout: cdk.Duration.seconds(300),
                role: get_results_lambda_role,
                vpcSubnets: this.vpc.selectSubnets({
                    subnetType: ec2.SubnetType.PRIVATE,
                }),
                securityGroups: [this.vpcDefaultSg],
                environment: {
                    STATE_TABLE_NAME: this.taskstatusTable.tableName,
                    STATE_TABLE_SERVICE: this.ddbService,
                    STATE_TABLE_CONFIG: this.ddbConfig,
                    TASKS_QUEUE_NAME: this.sqsQueue.queueName,
                    TASKS_QUEUE_DLQ_NAME: this.sqsDlq.queueName,
                    TASK_QUEUE_SERVICE: this.taskService,
                    TASK_QUEUE_CONFIG: this.taskConfig,
                    METRICS_ARE_ENABLED: this.metricsAreEnabled,
                    METRICS_GET_RESULTS_LAMBDA_CONNECTION_STRING:
                    this.metricsGetResultsLambdaConnectionString,
                    ERROR_LOG_GROUP: this.errorLogGroup,
                    ERROR_LOGGING_STREAM: this.errorLoggingStream,
                    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE: `${this.taskInputPassedViaExternalStorage}`,
                    GRID_STORAGE_SERVICE: this.gridStorageService,
                    S3_BUCKET: this.htcStdoutBucket.bucketName,
                    // Need to confirm if below is same as: aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address
                    REDIS_URL: this.elasticacheCluster.attrRedisEndpointAddress,
                    METRICS_GRAFANA_PRIVATE_IP: this.nlbInfluxdb,
                    REGION: this.region,
                },
            }
        );
        cdk.Tags.of(get_results_function).add("service", "htc-grid");
        return get_results_function;
    }
    private createCancelLambda(): lambdaPy.PythonFunction {
        const cancel_task_lambda_role = new iam.Role(
            this,
            "cancel_task_lambda_role",
            {
                roleName: this.lambdaNameCancelTasksRole,
                assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
                inlinePolicies: {
                    AssumeRole: this.lambdaStsAssumeRole,
                },
            }
        );
        const cancel_tasks_function = new lambdaPy.PythonFunction(
            this,
            "cancel_tasks_lambda_functions",
            {
                // If requirements.txt exists at entry path, don't need to explicitly state path like terraform
                entry: "../../../source/control_plane/python/lambda/cancel_tasks",
                index: "cancel_tasks.py",
                handler: "lambda_handler",
                layers: this.lambdaLayers,
                functionName: this.lambdaNameCancelTasks,
                runtime: lambda.Runtime.PYTHON_3_7,
                memorySize: 1024,
                timeout: cdk.Duration.seconds(300),
                role: cancel_task_lambda_role,
                vpcSubnets: this.vpc.selectSubnets({
                    subnetType: ec2.SubnetType.PRIVATE,
                }),
                securityGroups: [this.vpcDefaultSg],
                environment: {
                    STATE_TABLE_NAME: this.taskstatusTable.tableName,
                    STATE_TABLE_SERVICE: this.ddbService,
                    STATE_TABLE_CONFIG: this.ddbConfig,
                    TASKS_QUEUE_NAME: this.sqsQueue.queueName,
                    TASKS_QUEUE_DLQ_NAME: this.sqsDlq.queueName,
                    TASK_QUEUE_SERVICE: this.taskService,
                    TASK_QUEUE_CONFIG: this.taskConfig,
                    METRICS_ARE_ENABLED: this.metricsAreEnabled,
                    METRICS_CANCEL_TASKS_LAMBDA_CONNECTION_STRING:
                    this.metricsCancelTasksLambdaConnectionString,
                    ERROR_LOG_GROUP: this.errorLogGroup,
                    ERROR_LOGGING_STREAM: this.errorLoggingStream,
                    TASK_INPUT_PASSED_VIA_EXTERNAL_STORAGE:  `${this.taskInputPassedViaExternalStorage}`,
                    GRID_STORAGE_SERVICE: this.gridStorageService,
                    S3_BUCKET: this.htcStdoutBucket.bucketName,
                    // Need to confirm if below is same as: aws_elasticache_cluster.stdin-stdout-cache.cache_nodes.0.address
                    REDIS_URL: this.elasticacheCluster.attrRedisEndpointAddress,
                    METRICS_GRAFANA_PRIVATE_IP: this.nlbInfluxdb,
                    REGION: this.region,
                },
            }
        );
        cdk.Tags.of(cancel_tasks_function).add("service", "htc-grid");
        return cancel_tasks_function;
    }
    private createTtlLambda(): lambdaPy.PythonFunction {
        const ttl_checker_lambda_role = new iam.Role(
            this,
            "ttl_checker_lambda_role",
            {
                roleName: this.lambdaNameTtlCheckerRole,
                assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
                inlinePolicies: {
                    AssumeRole: this.lambdaStsAssumeRole,
                },
            }
        );

        const ttl_checker_function = new lambdaPy.PythonFunction(
            this,
            "ttl_checker_lambda_function",
            {
                // If requirements.txt exists at entry path, don't need to explicitly state path like terraform
                entry: "../../../source/control_plane/python/lambda/ttl_checker",
                index: "ttl_checker.py",
                handler: "lambda_handler",
                layers: this.lambdaLayers,
                functionName: this.lambdaNameTtlChecker,
                runtime: lambda.Runtime.PYTHON_3_7,
                memorySize: 1024,
                timeout: cdk.Duration.seconds(55),
                role: ttl_checker_lambda_role,
                vpcSubnets: this.vpc.selectSubnets({
                    subnetType: ec2.SubnetType.PRIVATE,
                }),
                securityGroups: [this.vpcDefaultSg],
                logRetention: logs.RetentionDays.FIVE_DAYS,
                // use_existing_cloudwatch_log_group = true
                environment: {
                    STATE_TABLE_NAME: this.taskstatusTable.tableName,
                    STATE_TABLE_SERVICE: this.ddbService,
                    STATE_TABLE_CONFIG: this.ddbConfig,
                    TASKS_QUEUE_NAME: this.sqsQueue.queueName,
                    TASKS_QUEUE_DLQ_NAME: this.sqsDlq.queueName,
                    TASK_QUEUE_SERVICE: this.taskService,
                    TASK_QUEUE_CONFIG: this.taskConfig,
                    METRICS_ARE_ENABLED: this.metricsAreEnabled,
                    METRICS_TTL_CHECKER_LAMBDA_CONNECTION_STRING:
                    this.metricsTtlCheckerLambdaConnectionString,
                    ERROR_LOG_GROUP: this.errorLogGroup,
                    ERROR_LOGGING_STREAM: this.errorLoggingStream,
                    METRICS_GRAFANA_PRIVATE_IP: this.nlbInfluxdb,
                    REGION: this.region,
                },
            }
        );
        cdk.Tags.of(ttl_checker_function).add("service", "htc-grid");
        return ttl_checker_function;
    }
    private enableLambdaLogging() {
        // CDK should create necessary permissions for event rule to trigger lambda target, will test
        new events.Rule(this, "ttl-checker-event-rule", {
            ruleName: `ttl_checker_event_rule-${this.projectName}`,
            description: "Fires event to trigger TTL Checker Lambda",
            schedule: events.Schedule.expression("rate(1 minute)"),
            targets: [new eventsTargets.LambdaFunction(this.ttlCheckerFunction)],
        });

        const globalErrorLogGroup = new logs.LogGroup(
            this,
            "global_error_group",
            {
                logGroupName: this.errorLogGroup,
                retention: logs.RetentionDays.TWO_WEEKS,
                removalPolicy: cdk.RemovalPolicy.DESTROY,
            }
        );

        new logs.LogStream(this, "global_error_stream", {
            logGroup: globalErrorLogGroup,
            logStreamName: this.errorLoggingStream,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
        });

        new iam.Policy(this, "lambda_logging_policy", {
            document: new iam.PolicyDocument({
                statements: [
                    new iam.PolicyStatement({
                        resources: ["arn:aws:logs:*:*:*"],
                        actions: [
                            "logs:CreateLogGroup",
                            "logs:CreateLogStream",
                            "logs:PutLogEvents",
                            "logs:DescribeLogStreams",
                        ],
                        effect: iam.Effect.ALLOW,
                    }),
                ],
            }),
            policyName: `lambda_logging_policy-${this.projectName}`,
            force: true,
            roles: [
                this.submitTaskFunction.role!,
                this.cancelTasksFunction.role!,
                this.getResultsFunction.role!,
                this.ttlCheckerFunction.role!,
            ],
        });

        new iam.Policy(this, "lambda_data_policy", {
            document: new iam.PolicyDocument({
                statements: [
                    new iam.PolicyStatement({
                        resources: ["*"],
                        actions: [
                            "sqs:*",
                            "dynamodb:*",
                            "firehose:*",
                            "s3:*",
                            "ec2:CreateNetworkInterface",
                            "ec2:DeleteNetworkInterface",
                            "ec2:DescribeNetworkInterfaces",
                        ],
                        effect: iam.Effect.ALLOW,
                    }),
                ],
            }),
            policyName: `lambda_data_policy-${this.projectName}`,
            force: true,
            roles: [
                this.submitTaskFunction.role!,
                this.cancelTasksFunction.role!,
                this.getResultsFunction.role!,
                this.ttlCheckerFunction.role!,
            ],
        });
    }
    private createPrivateApiGW(): [apigw.RestApi, apigw.IApiKey, string] {
        const privateApiGwPolicy = new iam.PolicyDocument({
            statements: [
                new iam.PolicyStatement({
                    principals: [new iam.AnyPrincipal()],
                    actions: ["execute-api:Invoke"],
                    resources: ["execute-api:/*/*/*"],
                    effect: iam.Effect.DENY,
                    conditions: {
                        StringNotEquals: {
                            "aws:SourceVpce": this.vpc.vpcId,
                        },
                    },
                }),
                new iam.PolicyStatement({
                    principals: [new iam.AnyPrincipal()],
                    actions: ["execute-api:Invoke"],
                    resources: ["execute-api:/*/*/*"],
                    effect: iam.Effect.ALLOW,
                }),
            ],
        });

        const privateApiGw = new apigw.RestApi(
            this,
            "htc_grid_private_rest_api",
            {
                restApiName: `${this.clusterName}-private`,
                description: "Private API Gateway for HTC Grid",
                endpointTypes: [apigw.EndpointType.PRIVATE],
                policy: privateApiGwPolicy,
                deploy: true,
                deployOptions: {
                    metricsEnabled: true,
                    loggingLevel: apigw.MethodLoggingLevel.INFO,
                    stageName: this.apiGatewayVersion,
                },
            }
        );

        // CDK should create necessary lambda:InvokeFunction permissions for api, will test to confirm
        privateApiGw.root
            .addResource("submit")
            .addMethod("POST", this.submitTaskIntegration, {
                apiKeyRequired: true,
            });

        privateApiGw.root
            .addResource("result")
            .addMethod("GET", this.getResultsIntegration, {
                apiKeyRequired: true,
            });

        privateApiGw.root
            .addResource("cancel")
            .addMethod("POST", this.cancelTasksIntegration, {
                apiKeyRequired: true,
            });

        const privateApiUsagePlan = privateApiGw.addUsagePlan(
            "private_rest_api_usage_plab",
            {
                name: this.clusterName,
                apiStages: [
                    {
                        api: privateApiGw,
                        stage: privateApiGw.deploymentStage,
                    },
                ],
            }
        );

        const secret = new secretsmanager.Secret(this, 'Secret', {
            generateSecretString: {
                excludeCharacters: ' %+~`#$&*()|[]{}:;<>?!\'/@"\\',
            },
        });
        const privateApiKey = privateApiGw.addApiKey("private_rest_api_key", {
            value: secret.secretValue.toString()
        });

        this.apiKey = privateApiKey

        privateApiUsagePlan.addApiKey(privateApiKey);
        return [privateApiGw, privateApiKey,""];
    }
    private createPublicApiGW(): apigw.RestApi {
        // ***** API Gateway Public *****
        // Will create Cloudwatch role with logs permissions, will need to validate they are proper permissions
        const public_api_gw = new apigw.RestApi(this, "htc_grid_public_rest_api", {
            restApiName: `${this.clusterName}-public`,
            description: "Public API Gateway for HTC Grid",
            endpointTypes: [apigw.EndpointType.REGIONAL],
            deploy: true,
            deployOptions: {
                metricsEnabled: true,
                loggingLevel: apigw.MethodLoggingLevel.INFO,
                stageName: this.apiGatewayVersion,
            },
        });

        const cognito_authorizer = new apigw.CognitoUserPoolsAuthorizer(
            this,
            "htc_grid_public_rest_api_cognito_authorizer",
            {
                authorizerName: `${this.clusterName}_cognito_authorizer`,
                cognitoUserPools: [this.cognitoUserpool],
            }
        );

        public_api_gw.root
            .addResource("submit")
            .addMethod("POST", this.submitTaskIntegration, {
                authorizationType: apigw.AuthorizationType.COGNITO,
                authorizer: cognito_authorizer,
            });

        public_api_gw.root
            .addResource("result")
            .addMethod("GET", this.getResultsIntegration, {
                authorizationType: apigw.AuthorizationType.COGNITO,
                authorizer: cognito_authorizer,
            });

        public_api_gw.root
            .addResource("cancel")
            .addMethod("POST", this.cancelTasksIntegration, {
                authorizationType: apigw.AuthorizationType.COGNITO,
                authorizer: cognito_authorizer,
            });
        return public_api_gw;
    }
}
