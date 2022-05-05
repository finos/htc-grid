import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"
import * as asg from "aws-cdk-lib/aws-autoscaling";
import * as cr from "aws-cdk-lib/custom-resources";
import * as eks from "aws-cdk-lib/aws-eks";
import * as ec2 from "aws-cdk-lib/aws-ec2";
import * as iam from "aws-cdk-lib/aws-iam";
import * as lambda from "aws-cdk-lib/aws-lambda";
import * as lambdaPy from "@aws-cdk/aws-lambda-python-alpha";
import * as events from "aws-cdk-lib/aws-events";
import { LambdaFunction } from "aws-cdk-lib/aws-events-targets";
import * as logs from "aws-cdk-lib/aws-logs";
import { IWorkerInfo } from "../shared/cluster-interfaces";
import * as path from "path";

interface LambdaDrainerScalingProps extends cdk.NestedStackProps {
  vpc: ec2.IVpc;
  vpc_default_sg: ec2.ISecurityGroup;
  cluster: eks.ICluster;
  worker_info: IWorkerInfo[];
  // nodeGroupBlocker: eks.Nodegroup[];
}

export class LambdaDrainerScalingStack extends cdk.NestedStack {
  private vpc: ec2.IVpc;
  private vpc_default_sg: ec2.ISecurityGroup;
  private cluster: eks.ICluster;
  private worker_info: IWorkerInfo[];
  // private nodeGroupBlocker: eks.Nodegroup[];

  private readyCheckProvider: cr.Provider;

  constructor(
    scope: Construct,
    id: string,
    props: LambdaDrainerScalingProps
  ) {
    super(scope, id, props);

    this.vpc = props.vpc;
    this.vpc_default_sg = props.vpc_default_sg;
    this.cluster = props.cluster;
    this.worker_info = props.worker_info;

    this.readyCheckProvider = this.createReadyCheckHandler();

    const drainer_function = this.createDrainerFunction();
    this.createAutoscalingEvent(drainer_function);
    // this.addDrainerEksRole();
    const scaling_function = this.createScalingFunction();
    this.createScalingMetricsEvent(scaling_function);
  }
  private createReadyCheckHandler() {
    const handler = new lambda.Function(this, "CheckNodegroupStatus", {
      code: lambda.Code.fromAsset(
        path.join(__dirname, "../shared/nodegroup-checker")
      ),
      handler: "index.handler",
      runtime: lambda.Runtime.PYTHON_3_7,
      timeout: cdk.Duration.minutes(15),
    });
    handler.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["eks:DescribeNodegroup"],
        resources: ["*"],
      })
    );
    return new cr.Provider(this, "NodegroupReadyProvider", {
      onEventHandler: handler,
    });
  }
  private createDrainerFunction(): lambdaPy.PythonFunction {
    // Is this needed? CDK should create this, but may create extra permissions as well..
    const function_role = new iam.Role(this, "drainer_lambda_role", {
      roleName: `role_lambda_drainer-${this.node.tryGetContext("tag")}`,
      assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
      inlinePolicies: {
        AssumeRole: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ["sts:AssumeRole"],
              effect: iam.Effect.ALLOW,
              resources: ["*"],
            }),
          ],
        }),
      },
    });
    const drainer_function = new lambdaPy.PythonFunction(
      this,
      "drainer-function",
      {
        entry: "../../../source/compute_plane/python/lambda/drainer",
        index: "handler.py",
        handler: "lambda_handler",
        functionName: `lambda_drainer-${this.node.tryGetContext("tag")}`,
        runtime: lambda.Runtime.PYTHON_3_7,
        memorySize: 1024,
        timeout: cdk.Duration.seconds(900),
        role: function_role,
        vpcSubnets: this.vpc.selectSubnets({
          subnetType: ec2.SubnetType.PRIVATE,
        }),
        securityGroups: [this.vpc_default_sg],
        environment: {
          CLUSTER_NAME: this.cluster.clusterName,
        },
      }
    );
    cdk.Tags.of(drainer_function).add("service", "htc-aws");
    // Agent permissions
    // Believe CDK will already add this, but adding for terraform: cdk consistency (for now)
    function_role.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName(
        "service-role/AWSLambdaBasicExecutionRole"
      )
    );
    new iam.Policy(this, "lambda_drainer_policy", {
      document: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            resources: ["*"],
            actions: [
              "ec2:CreateNetworkInterface",
              "ec2:DeleteNetworkInterface",
              "ec2:DescribeNetworkInterfaces",
              "autoscaling:CompleteLifecycleAction",
              "ec2:DescribeInstances",
              "eks:DescribeCluster",
              "sts:GetCallerIdentity",
            ],
            effect: iam.Effect.ALLOW,
          }),
        ],
      }),
      policyName: "lambda-drainer-policy",
      roles: [function_role],
    });
    return drainer_function;
  }

  private createAutoscalingEvent(lambda: lambdaPy.PythonFunction) {
    const timeout = this.node.tryGetContext("graceful_termination_delay");
    const lambda_target = new LambdaFunction(lambda);
    this.worker_info.forEach((worker, index) => {
      const autoScalingGroup = this.getAutoScalingGroupFromNodeGroup(
        worker.configs.name
      );
      autoScalingGroup.node.addDependency(worker.nodegroup);
      const asg_name = autoScalingGroup.autoScalingGroupName;
      // asg.addLifeCycleHook requires a target, have to use CfnLifecycleHook
      new asg.CfnLifecycleHook(this, `drainer_hook_${worker.configs.name}`, {
        autoScalingGroupName: asg_name,
        lifecycleTransition: asg.LifecycleTransition.INSTANCE_TERMINATING,
        defaultResult: asg.DefaultResult.ABANDON,
        heartbeatTimeout: timeout,
        lifecycleHookName: worker.configs.name,
      });
      new events.Rule(this, `event-lifecyclehook-${index}`, {
        ruleName: `event-lifecyclehook-${index}`,
        description: "Fires event when an EC2 instance is terminated",
        targets: [lambda_target],
        eventPattern: {
          detailType: ["EC2 Instance-terminate Lifecycle Action"],
          source: ["aws.autoscaling"],
          detail: {
            AutoScalingGroupName: [asg_name],
          },
        },
      });
    });
  }
  // lambda_drainer-eks.tf
  // Error when trying to add:
  // 'Error from server (AlreadyExists): error when creating "/tmp/manifest.yaml":
  // clusterroles.rbac.authorization.k8s.io "lambda-cluster-access" already exists\n'
  // commenting out for now
  // private addDrainerEksRole() {
  //     const cluster_role_name = 'lambda-cluster-access';
  //     const cluster_role = {
  //         apiVersion: 'rbac.authorization.k8s.io/v1',
  //         kind: 'ClusterRole',
  //         metadata: {
  //             name: cluster_role_name
  //         },
  //         rules: [
  //             {
  //                 apiGroups: [""],
  //                 resources: ["pods", "pods/eviction", "nodes"],
  //                 verbs: ["create", "list", "patch"]
  //             }
  //         ]
  //     };
  //     const cluster_role_binding = {
  //         apiVersion: 'rbac.authorization.k8s.io/v1',
  //         kind: 'RoleBinding',
  //         metadata: {
  //             name: 'lambda-user-cluster-role-binding'
  //         },
  //         subjects: [
  //             {
  //                 kind: 'User',
  //                 name: 'lambda'
  //             }
  //         ],
  //         roleRef: {
  //             kind: 'ClusterRole',
  //             name: cluster_role_name,
  //             apiGroup: 'rbac.authorization.k8s.io'
  //         }
  //     };
  //     const role_manifest = new eks.KubernetesManifest(this, 'lambda_cluster_role', {
  //         cluster: this.cluster,
  //         manifest: [cluster_role]
  //     });
  //     const role_binding_manifest = new eks.KubernetesManifest(this, 'lambda_cluster_role_binding', {
  //         cluster: this.cluster,
  //         manifest: [cluster_role_binding]
  //     });
  //     role_binding_manifest.node.addDependency(role_manifest);
  // }
  private createScalingFunction(): lambdaPy.PythonFunction {
    const lambda_name = `${this.node.tryGetContext(
      "lambda_name_scaling_metrics"
    )}-${this.node.tryGetContext("tag")}`;
    // Is this needed? CDK should create this, but may create extra permissions as well..
    const function_role = new iam.Role(this, "role_lambda_metrics", {
      roleName: `role_lambda_metrics-${this.node.tryGetContext("tag")}`,
      assumedBy: new iam.ServicePrincipal("lambda.amazonaws.com"),
      inlinePolicies: {
        AssumeRole: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              actions: ["sts:AssumeRole"],
              effect: iam.Effect.ALLOW,
              resources: ["*"],
            }),
          ],
        }),
      },
    });
    const scaling_function = new lambdaPy.PythonFunction(this, lambda_name, {
      entry: "../../../source/compute_plane/python/lambda/scaling_metrics",
      index: "scaling_metrics.py",
      handler: "lambda_handler",
      functionName: lambda_name,
      runtime: lambda.Runtime.PYTHON_3_7,
      memorySize: 1024,
      timeout: cdk.Duration.seconds(60),
      role: function_role,
      vpcSubnets: this.vpc.selectSubnets({
        subnetType: ec2.SubnetType.PRIVATE,
      }),
      securityGroups: [this.vpc_default_sg],
      environment: {
        STATE_TABLE_CONFIG: this.node.tryGetContext("ddb_state_table"),
        NAMESPACE: this.node.tryGetContext("namespace_metrics"),
        DIMENSION_NAME: this.node.tryGetContext("dimension_name_metrics"),
        DIMENSION_VALUE: this.cluster.clusterName,
        PERIOD: this.node.tryGetContext("period_metrics"),
        METRICS_NAME: this.node.tryGetContext("metrics_name"), // metrics_name in variables.tf, but metric_name in lambda_scaling.tf... need to investigate
        SQS_QUEUE_NAME: this.node.tryGetContext("sqs_queue"),
        REGION: this.region,
        TASK_QUEUE_SERVICE: this.node.tryGetContext("task_queue_service"),
        TASK_QUEUE_CONFIG: this.node.tryGetContext("task_queue_config"),
      },
      logRetention: logs.RetentionDays.FIVE_DAYS,
    });
    cdk.Tags.of(scaling_function).add("service", "htc-aws");
    new iam.Policy(this, "lambda_metrics_logging_policy", {
      document: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            resources: ["arn:aws:logs:*:*:*"],
            actions: [
              "logs:CreateLogGroup",
              "logs:CreateLogStream",
              "logs:PutLogEvents",
            ],
            effect: iam.Effect.ALLOW,
          }),
        ],
      }),
      policyName: "lambda_metrics_logging_policy",
      roles: [function_role],
    });
    new iam.Policy(this, "lambda_metrics_data_policy", {
      document: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            resources: ["*"],
            actions: [
              "dynamodb:*",
              "sqs:*",
              "cloudwatch:PutMetricData",
              "ec2:CreateNetworkInterface",
              "ec2:DeleteNetworkInterface",
              "ec2:DescribeNetworkInterfaces",
            ],
            effect: iam.Effect.ALLOW,
          }),
        ],
      }),
      policyName: "lambda_metrics_data_policy",
      roles: [function_role],
    });
    return scaling_function;
  }
  // Should add necessary permissions for rule to invoke
  private createScalingMetricsEvent(lambda: lambdaPy.PythonFunction) {
    const rule_name = "scaling_metrics_event_rule";
    const schedule_expression = this.node.tryGetContext(
      "metrics_event_rule_time"
    );
    const lambda_target = new LambdaFunction(lambda);
    new events.Rule(this, rule_name, {
      ruleName: rule_name,
      description: "Fires event rule to put metrics",
      schedule: events.Schedule.expression(schedule_expression),
      targets: [lambda_target],
    });
  }
  // No built in way to get ASG associated with nodegroup
  // The ASG is needed for drainer
  private getAutoScalingGroupFromNodeGroup(
    node: string
  ): asg.IAutoScalingGroup {
    const nodegroupReady = new cdk.CustomResource(
      this,
      `${node}NodegroupReady`,
      {
        serviceToken: this.readyCheckProvider.serviceToken,
        properties: {
          Cluster: this.cluster.clusterName,
          Nodegroup: node,
        },
      }
    );
    const describe_node_group = new cr.AwsCustomResource(
      this,
      `nodegroup_description_${node}`,
      {
        policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
          resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
        }),
        onCreate: {
          physicalResourceId: cr.PhysicalResourceId.fromResponse(
            "nodegroup.nodegroupName"
          ),
          service: "EKS",
          action: "describeNodegroup",
          region: this.region,
          parameters: {
            clusterName: this.cluster.clusterName,
            nodegroupName: node,
          },
        },
      }
    );
    // Nodegroup takes some time to become active, need to wait for nodegroup to be active before fetching ASG name
    describe_node_group.node.addDependency(nodegroupReady);
    const node_group_asg_name = describe_node_group?.getResponseField(
      "nodegroup.resources.autoScalingGroups.0.name"
    );
    return asg.AutoScalingGroup.fromAutoScalingGroupName(
      this,
      `nodegroup_asg_${node}`,
      node_group_asg_name!
    );
  }
}
