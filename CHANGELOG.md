### CHANGELOG

All notable changes to this project will be documented in this file. Dates are displayed in UTC.

#### [v0.4.3](https://github.com/awslabs/aws-htc-grid/compare/v0.4.2...v0.4.3)

> 6 December 2023

### Terraform State:
- Encrypt and secure `init_grid` state and Lambda buckets.
- Limit the scope of KMS Key policy for State Buckets.
- Remove `AccessControls` and use `BucketPolicy` to keep the bucket private.
- Configure all Makefiles to use encrypted S3 Buckets for TF State, non-root Dockerfiles, fix HTCGRID_ECR_REPO, name CloudFormation stack outputs, and support updating existing `init_grid` stack.
- Improve `init_grid` Makefile to handle initial and deletion cases better.
- Add support for cleaning up S3 object versions and standardize bucket variable naming.

### HTC Grid Containers:
- Configure all Dockerfiles to run non-root containers and fix builds.
- Configure all HTC K8S resources to run with `runAsNonRoot`, default `seccompProfile`, and disabled `allowPrivilegeEscalation`.
- Rename components, add `readOnlyFileSystem` and seccomp profile to HTC Agent, fix and cleanup code.
- Remove file system write dependencies for the agent.
- Harden K8S manifests and enforce further chekov rules.
- Configure Grafana Ingress to drop invalid HTTP Header fields.

### HTC Grid Control Plane:
- Configure CMK KMS Key encryption for VPC Flow Logs, ECR Repositories, SQS, DynamoDB, S3, EKS Cluster, EKS MNG EBS Volumes, and all CloudWatch Logs.
- Add encrypted CloudWatch Logging for API Gateway.
- Create S3 via TF Module, add encryption support for S3 Data Plane in the agent, fix AWS partition, and DNS Suffix usage.
- Simplify code and move all lambdas and auth to the `control_plane`.
- Configure and consolidate least-privilege permissions on KMS, Lambda, and Agent IAM policies.
- Add KMS `Decrypt` and `GenerateDataKey` permissions to Lambda and Agent permissions.
- Move installation of `jq` onto lambda images and fix the bootstrap script.
- Convert EC Redis to a single replica cluster mode and add encryption.
- Add AUTH for ElastiCache Redis Cluster.
- Enable XRay tracing for Lambda functions and adjust Redis config.
- Add an explicit ASG Service Linked Role declaration to enable KMS support for ASG EBS Volumes.
- Handle cases where `AWSServiceRoleForAutoScaling` already exists.
- Add S3 and SQS Resource Policies to enforce HTTPS and create separate CMK KMS Keys for DLQs per each SQS Queue.
- Configure the DLQs to be used with the respective SQS Queues and fix naming/references.
- Add security group and ACL controls where possible.
- Configure `securityContext` for OpenAPI.

### General:
- Add GitHub workflows for `cfn_lint`, `trivy`, and `checkov`.
- Standardize, fix, and simplify tests.
- Standardize the naming of TF resources.
- Fix docs and `random_password` to align with pipelines.
- Add auto deploy & destroy stages for images.

### Cloud9:
- Fix Cloud9 deployment script to target correct instances.
- Fix Cloud9 bootstrap race condition and adjust to WS.
- Force a reinstall at bootstrap time to fix virtualenv issues.
- Add support for specifying a Git repo/branch for HTCGridSource.
- Remove Admin role from KMS Admins as it doesn't exist in WS.


#### [v0.4.2](https://github.com/awslabs/aws-htc-grid/compare/v0.4.1...v0.4.2)

> 4 October 2023

- Remove `CDK` as IaC for deploying HTC Grid
- Remove any hardcoded dependency to `urllib3`
- Migrate lambda function runtime  from python 3.7 to python 3.11


#### [v0.4.1](https://github.com/awslabs/aws-htc-grid/compare/v0.4.0...v0.4.1)

> 14 September 2023

- Move the deployment of the Helm charts outside of the `EKS Blueprints Addons` module to native TF Resource(s) to better handle the resource dependencies to those addons and simplify code.
- Switch Grafana ingress to use the new `ingressClassName` spec format instead of the deprecated `kubernetes.io/ingress.class` annotation.
- Switch to using the `kubernetes_annotations` TF Resource to manage the Cognito annotations for Grafana Ingress.
- Adjust workshop notes on creation of Cognito user for the user-pool with sign-up disabled.
- Add ability to always use the `latest` released tag in the Cloud9 instance deployment.
- Fix the Private API Gateway and Resource Policy race-condition/dependency.
- Fix `image_repository` destroy issues since adding explicit region flags to ECR commands.
- Fix missing comma in `state_table_dynamodb.py`.
- Add explicit region flag when listing ECR repos in the workshop.
- Clean up and adjust workshop notes, code, comments and other docs (ie the FSI Whitepaper link).

#### [v0.4.0](https://github.com/awslabs/aws-htc-grid/compare/v0.3.6...v0.4.0)

> 11 September 2023

### EKS Cluster & Nodes:
- Change to using [terraform-aws-modules/eks](https://registry.terraform.io/modules/terraform-aws-modules/eks/aws/latest) for managing and deploying the EKS Cluster as well as related resources, such as: Node IAM Roles & Policies, Node Defaults incl. instance types, Security Groups and the AWS Auth ConfigMap.
- Change to using [EKS Managed Node Groups](https://docs.aws.amazon.com/eks/latest/userguide/managed-node-groups.html) for all of the Core and Worker Node Groups.
- Configure [Cluster Autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler) to manage the scaling and lifecycle of the EKS Managed Node Groups.
- Disable AWS Node Termination Handler, as it shouldn't be used in conjunction with EKS Managed Node Groups.
- Simplify and standardise VPC Endpoint creation. Add EKS Private VPC Endpoint to allow internal communications from the private subnet with the EKS Control Plane.
- Change node taints from `grid/type: Operator` to `htc/node-type: core` and `htc/node-type: worker`. Add those as labels and tags as well, to simplify operations and cluster visibility via kubectl and other monitoring solutions.
- Adjust default instance types for the Core and Worker Node Groups to allow for better diversification and deplopyment, both for OnDemand and Spot workloads.
- Change to using `cluster_name` instead of `eks_cluster_id` everywhere, in line with the new module changes.
- Add ability to specify EBS Volume type and size for the EKS Nodes.

### EKS AddOns:
- Change to [eks-blueprints-addons](https://registry.terraform.io/modules/aws-ia/eks-blueprints-addons/aws/latest) for managing and deploying all of the EKS Blueprint AddOns and OSS Helm Releases, such as: CoreDNS, Kube-Proxy, VPC CNI, FluentBit, Cluster Autoscaler, AWS LoadBalancer Controller, CloudWatch Metrics, KEDA, InfluxDB, Prometheus & Grafana, as well as **all** the relevant configuration.
- Add implicit and explicit dependencies to fix the race conditions where the `AWS Loadbalancer Controller` may get deleted before being able to cleanup the AWS resources that it manages. The new dependency order guarantees a proper clean up of those resources before the `AWS LoadBalancer Controller` is destroyed during unprovisioning.
- Fix the explicit and implicit dependencies between the Kubernetes data sources and the underlying resources created by the `EKS Blueprints Addons` module.
- Move ingress and dashboard creation for Grafana to be handled via the Helm chart and clean up the un-needed additional Terraform resources. Add the Grafana Ingress URL as a Terraform output for the module.
- Adjust image and repo configuration to pull the correct version for `Cluster Autoscaler` and other components.
- Adjust the node selectors for FluentBit and CloudWatch agent DaemonSets to deploy to all nodes.
- Switch to using the new Go based high-performance FluentBit logger for CloudWatch.
- Disable Grafana Live Server (as it requires WebSockets).
- Add cookie based session stickiness to the Grafana ingress to allow the ALB Controller and the Grafana HA deployment to handle auth properly.
- Fix FluentBit based Container Insights Logs.
- Extend the CoreDNS creation timeout to 25Mins to allow for the control plane to self-heal in case of issues.

### HTC-Grid:
- Change to using [eks-blueprints-addon](https://registry.terraform.io/modules/aws-ia/eks-blueprints-addon/aws/latest) for deploying the HTC-Grid Helm Chart as well as create the respective [IRSA Role](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html).
- Adjust IAM Policies & Permissions (ensuring CloudWatch Log Group lifecycle handling is done via Terraform), as well as formatting and naming to ensure concsistency for all the Lambdas.
- Split the Control Plane lambda defintions into their individual TF files, simplifying configuration and visibility and grouping for the resources created.

### Terraform & Helm:
- Adjust all of the Terraform Registry modules to use `~>` version pinning, allowing any new non-major versions to be used (any minor and patch updates are allowed), simplifying dependency version updates and ensuring consistency.
- Upgrade all of the Terraform modules from the Terraform Registry to use the **current latest** versions.
- Upgrade all of the Terraform providers to use the latest available versions and major version pinning using thre `~>` operator.
- Upgrade all of the Helm charts and container images to the current latest version for all of the components.
- Remove image level pinning of Helm AddOn components and pinned only using the Helm release versions.
- Remove un-needed explicit `depends_on` statemenets which cause slowness and cyclic dependencies or failures on plan (by not allowing data sources to be computed before an apply).
- Fix cyclic dependency and remove the need for running targeted applies for the IAM Policies for the EKS Pull Through Cache and Agent permissions in the `apply`/`auto-apply` stages.
- Move to using `aws_api_gateway_rest_api_policy` instead of a direct policy attachment of a generic policy for `OpenAPI Private`, which showed changes on every `terraform apply`, due to the wildcard allow policy.
- Configure the AWS CloudWatch Metrics and AWS for FluentBit deployments to run on the `Core` nodes.
- Configure Grafana to start two replicas and spread them across different nodes for high availability.
- Clean up the Helm chart `values.yaml` files, removing any unneeded and nrequired config, simplifying the deployments. Consolidating Helm chart versions into a single variable for ease of change and visibility.
- Remove un-needed data sources and use module outputs as required to also enforce consistent implicit dependencies in Terraform.
- Simplify and consolidate the variable definitions, usage and functions across all of the resources and modules.
- Adjust output and variable descriptions, types and values to reflect the required information and ensure consistency.
- Adjust provider configurations to ensure correct credential retrieval and handling.
- Use `aws_htc_ecr` consistently across all of the Helm charts as the ECR source repository for pulling internal and pull-through images.

### New Features:
- Upgrade `ElastiCache` to version 7 and started using the ***AWS Graviton3*** based `cache.r7g.large` instance(s) for the Redis cluster.
- Add ability to do in-place upgrades of the `ElastiCache` clusters by versioning the `Parameter Groups` created/used.
- Add `watch_htc.sh` script, which can be used to monitor the status of a Kubernetes job running tasks on HTC-Grid, as well as the status of the overall compute plane, including the HPA, Deployment, Nodes and Job Completion statuses as well as durations. The scripts takes two arguments, namely the namespace to be watched as well as the name of the Kubernetes job.
- Add support for correct handling of the `AWS Partition` as well as `AWS Partition DNS Suffix`.
- Add ability to automatically manage the lifecycle of the self-signed ALB Certificates via the deployment process (any certs about to expire will get automatically updated and rolled out without any downtime).
- Migrate to using `AWS Certificate Manager` instead of the `IAM Server Certificates` for the ALB Certs.
- Increase the self-signed ALB Cert validity to 1 year, with auto-renew if run within 6 months of expiration time
- Add ability to automatically create, update and destroy an `admin` Cognito user via the deployment, to be used for the Grafana authentication, reducing the need for manual steps during the setup as well as the workshop.
- Add user cleanup on `destroy` for the `admin` Cognito user (created for use with Grafana) as well as the relevant Cognito config with the Grafana Ingress.
- Switch to creating the Cognito User for Grafana using TF native resources.
- Switch the `grafana_admin_password` variable to be sensitive everywhere.
- Add template file and generation for submitting a batch of multi-session tasks instead of copying/replacing at runtime of the workshop. Adjust docs/workshop accordingly.

### Lambda Runtimes:
- Unify all of the `lambda_runtimes` into a single Dockerfile, driving behavior via build time arguments.
- Add package updates at build time (incl. cache clearing post updates), to ensure latest versions of updates are always included in the runtime images.
- Migrate all build runtimes to use the ECR Pull Through Cache for the build images.
- Simplify and consolidated the lambda runtime build and push Terraform resources into a single map of resources.
- Fix Lambda Runtimes Dockerfile to handle different entrypoint source script for the provided runtime.

### ECR & Image Builds:
- Change all container images to use the ECR pull through-cache where possible.
- Add a new pull-through-cache config for `registry.k8s.io`, to allow for pulling any cluster components automatically, i.e. the `cluster-autoscaler`.
- Add flag (`REBUILD_RUNTIMES`) which allows re-creating the local images for all the runtimes (without using the cache) and pushing them to ECR.
- Clean up `image_repository` keeping the minimum number of required external dependencies (that were not availble via an ECR Pull Through Cache), to be manually copied over to the local ECR repositories.
- Add the ability to cleanup the ECR Pull Through Cache repositories upon running `destroy-images`.
- Add image scanning on push/upload for all of the ECR Repositories.
- Move to using `for_each` instead of `count` for ECR Repositories ensuring they don't get destroyed from a simple order change in the JSON Config.

### Cloud9:
- Fix all of the Cloud9 bootstrap errors, handling of different packages, correct installation and upgrade of all the components and improved the bootstrap logging to increase visibilty on the success or issues of the Cloud9 deployment.
- Update default versions for all pre-requisites for the Cloud9 environment to the latest versions.
- Add support for using main (i.e. downloading the current HEAD version of the repo) as a value for `HTCGridVersion` when deploying the Cloud9 environment.

### Docs:
- Adjust workshop texts, screenshots and configs to reflect the latest changes introduced as part of this or previous PRs and give instructions on any possible deploy time issues and how to fix them.
- Add instructions on how to use the `watch-htc.sh` script for monitoring jobs and deployments.
- Add the quick one-command based option for disabling of Cloud9 Managed Temporary Credentials.
- Adjust wording, correct grammar mistakes and other typos and simplify language.
- Extend workshop cleanup steps to handle local state cleaning as well.

### Misc.:
- Add `CHANGELOG.md` to the repository, including reflecting all of the previous releases and commits.
- Format all of the deployment files to ensure consistency in naming, spacing, newlines, etc.
- Adjust wording, correct grammar mistakes and other typos across comments and other texts.
- Cleanup old and unused files, charts, configs and commented out code.
- Fix the clean stage in the `init_grid` Makefile.
- Add `load_variables.sh` to `.gitignore`.
- Update all Copyright notices to reflect the current year (2023).


#### [v0.3.6](https://github.com/awslabs/aws-htc-grid/compare/v0.3.5...v0.3.6)

> 19 July 2023

- Adding support for Java based Lambda Workers [`#64`](https://github.com/awslabs/aws-htc-grid/pull/64)
- Adding automated Bandit security checks for pull requests [`#55`](https://github.com/awslabs/aws-htc-grid/pull/55)
- DynamoDB degrading state refactoring [`#52`](https://github.com/awslabs/aws-htc-grid/pull/52)
- Fixing instance profile association in the context of Config rule [`#51`](https://github.com/awslabs/aws-htc-grid/pull/51)
- Fix: automatically added timestamp upon task completion into DDB  [`#43`](https://github.com/awslabs/aws-htc-grid/pull/43)
- Fixing Cloud9 deployment outside of EventEngine [`#46`](https://github.com/awslabs/aws-htc-grid/pull/46)
- Adding CDK has a deployment tool for the HTC Grid [`#39`](https://github.com/awslabs/aws-htc-grid/pull/39)
- demo update [`2215871`](https://github.com/awslabs/aws-htc-grid/commit/2215871f63501ff2bead8b3e15a890fc5155d25c)
- feat: migration tentative to EKS blueprint [`d65abca`](https://github.com/awslabs/aws-htc-grid/commit/d65abca29594e4af0c82f1bb4b55da85f378acd7)
- Adding Java runtime for Worker Lambdas + QuantLib example [`9444a17`](https://github.com/awslabs/aws-htc-grid/commit/9444a17150737bcc977283c97710eb1b9a23e774)


#### [v0.3.5](https://github.com/awslabs/aws-htc-grid/compare/v0.3.4...v0.3.5)

> 27 February 2022

- fixed issue in cloud9 environment [`#38`](https://github.com/awslabs/aws-htc-grid/pull/38)


#### [v0.3.4](https://github.com/awslabs/aws-htc-grid/compare/v0.3.3...v0.3.4)

> 27 February 2022

- Fixing entry in quantlib example [`#37`](https://github.com/awslabs/aws-htc-grid/pull/37)
- adding the right args to quantlib [`d204446`](https://github.com/awslabs/aws-htc-grid/commit/d204446c3dabae9f133ecf7d0d243e563ec5fe96)


#### [v0.3.3](https://github.com/awslabs/aws-htc-grid/compare/v0.3.2...v0.3.3)

> 25 February 2022

- fix:  python example for through pull cache [`310301d`](https://github.com/awslabs/aws-htc-grid/commit/310301d9e4987c14e48a759c740f4b4027fb68d5)


#### [v0.3.2](https://github.com/awslabs/aws-htc-grid/compare/v0.3.1...v0.3.2)

> 24 February 2022

- ECR Pull through fixes  [`#35`](https://github.com/awslabs/aws-htc-grid/pull/35)
- Cancel Tasks [`#32`](https://github.com/awslabs/aws-htc-grid/pull/32)
- SQS Queue Abstraction and Priority Queues Support [`#33`](https://github.com/awslabs/aws-htc-grid/pull/33)
- SQS Priority queues support initial version [`ccf31f4`](https://github.com/awslabs/aws-htc-grid/commit/ccf31f49e8d260aff169420dd322459a16081a9d)
- Refactoring [`1f86e28`](https://github.com/awslabs/aws-htc-grid/commit/1f86e281c07e57befcc2124f98ae74996fbe77ed)
- Added cancellation of  tasks in processing state [`b22ce80`](https://github.com/awslabs/aws-htc-grid/commit/b22ce80475a3cfdcb5912237d2fcd62827934468)


#### [v0.3.1](https://github.com/awslabs/aws-htc-grid/compare/v0.3.0...v0.3.1)

> 15 September 2021

- fix:(issue 28) improving documentation, makefile and image transfer [`a8569d5`](https://github.com/awslabs/aws-htc-grid/commit/a8569d55bff158eb4c13ae206df0c65981f418a7)
- fix: migrating to versin 0.3.1 [`9f1af13`](https://github.com/awslabs/aws-htc-grid/commit/9f1af131b2c94744b785b3149a1c20846bc57b47)


#### [v0.3.0](https://github.com/awslabs/aws-htc-grid/compare/v0.2.0...v0.3.0)

> 14 September 2021

- migrating documentation to mkdocs [`#24`](https://github.com/awslabs/aws-htc-grid/pull/24)
- Workshop: adding tasks state transition diagram [`#21`](https://github.com/awslabs/aws-htc-grid/pull/21)
- using openAPI as a defintion of API Gateway [`#20`](https://github.com/awslabs/aws-htc-grid/pull/20)
- Replacing lambci by lambda-rie [`#19`](https://github.com/awslabs/aws-htc-grid/pull/19)
- State Table abstraction layer [`#18`](https://github.com/awslabs/aws-htc-grid/pull/18)
- Workshop initial [`#17`](https://github.com/awslabs/aws-htc-grid/pull/17)
- HTC-Grid Workshop  [`#16`](https://github.com/awslabs/aws-htc-grid/pull/16)
- initial commit [`0f6bfa9`](https://github.com/awslabs/aws-htc-grid/commit/0f6bfa9f4bfa1f507c955907f982516fc913952d)
- initial commit [`c38747b`](https://github.com/awslabs/aws-htc-grid/commit/c38747bc80704e16a85c62b1137d8531b3a87de6)
- main sections completed [`572bee2`](https://github.com/awslabs/aws-htc-grid/commit/572bee2730bd1f96ec3ad7b8f9f9bf474bd85e82)


#### [v0.2.0](https://github.com/awslabs/aws-htc-grid/compare/v0.1.0...v0.2.0)

> 30 July 2021

- Upstream Influxdb Helm Chart got Updated to 1.8.6 [`#15`](https://github.com/awslabs/aws-htc-grid/pull/15)
- Update images_config.json [`#1`](https://github.com/awslabs/aws-htc-grid/pull/1)
- Fix  version in image repository and update of version in the cloud9 template [`#14`](https://github.com/awslabs/aws-htc-grid/pull/14)
- Update version for VPC module and image transfer [`#13`](https://github.com/awslabs/aws-htc-grid/pull/13)
- EKS Update + other third parties [`#12`](https://github.com/awslabs/aws-htc-grid/pull/12)
- add SSM agent and code refactoring [`#11`](https://github.com/awslabs/aws-htc-grid/pull/11)
- Fix spelling error [`#10`](https://github.com/awslabs/aws-htc-grid/pull/10)
- There have been a few changes to the helm prometheus version. Some of them were incompatible with the versions that we we were using. The terraform/variables.tf and the images in the image repository for alertmanager, kube-state-metrics, node-exporter and prometheus have been updated to the latest version as in the ones used in master and the latest version for https://github.com/prometheus-community/helm-charts. Then tested. There might be some changes required in the Dashboards given the change in metrics but all is working back well. [`#9`](https://github.com/awslabs/aws-htc-grid/pull/9)
- HTC-Grid Development first draft [`#8`](https://github.com/awslabs/aws-htc-grid/pull/8)
- Adding QuantLib sample workload [`#7`](https://github.com/awslabs/aws-htc-grid/pull/7)
- fix: string validation improved for cognito domain name [`#6`](https://github.com/awslabs/aws-htc-grid/pull/6)
- Fix: Lambda version module and S3 bucket operation in fully private VPC [`#5`](https://github.com/awslabs/aws-htc-grid/pull/5)
- Compliance with terraform 0.15.0 and new example added [`#3`](https://github.com/awslabs/aws-htc-grid/pull/3)
- Fix a minor spelling mistake [`#4`](https://github.com/awslabs/aws-htc-grid/pull/4)
- fix(dataplane): client timed out while putting data in S3  [`#2`](https://github.com/awslabs/aws-htc-grid/pull/2)
- Fixed url in the Cloud9 dev [`#1`](https://github.com/awslabs/aws-htc-grid/pull/1)
- Add python client/worker portfolio eval. using QuantLib [`0d299df`](https://github.com/awslabs/aws-htc-grid/commit/0d299df7622ba637bbf36e90c69530637a30e8b9)
- fix: updating version associated to the grid and the cloud9 environment [`98b6b17`](https://github.com/awslabs/aws-htc-grid/commit/98b6b17071de0fd8bfc68bf55b816132e305c74e)
- fix: fix indentation [`a20cca8`](https://github.com/awslabs/aws-htc-grid/commit/a20cca8a24cbe92eac450c4f989a537a7ced396a)


#### v0.1.0

> 14 April 2021

- HTC-Grid Initial Commit [`1ddc3ab`](https://github.com/awslabs/aws-htc-grid/commit/1ddc3ab909d6b499a0a0ff3bb675a2622e9322b6)
- Initial commit [`5512550`](https://github.com/awslabs/aws-htc-grid/commit/5512550c94e7e062280cb1efbea22f5368774d6e)
- Readme points to Cloud9 dev link [`f0ed206`](https://github.com/awslabs/aws-htc-grid/commit/f0ed206ae72c02caaccb992b7a4ae589c7361319)
