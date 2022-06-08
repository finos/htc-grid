//vpc.ts
import {Construct} from "constructs";
import * as cdk from "aws-cdk-lib";
import * as ec2 from "aws-cdk-lib/aws-ec2";


export interface VpcStackProps extends cdk.StackProps {

  project: string;
  clusterName: string;

  publicSubnets: number;
  privateSubnets: number;
  enablePrivateSubnet: boolean;

}

export class VpcStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly defaultSecurityGroup: ec2.ISecurityGroup;

  private project: string;
  private clusterName: string;
  public privateSubnetSelector: ec2.SubnetSelection;
  public publicSubnetSelector: ec2.SubnetSelection;

  constructor(scope: Construct, id: string, props: VpcStackProps) {
    super(scope, id, props);

    this.project = props.project;
    this.clusterName = props.clusterName;


    this.vpc = this.createVpc(props.enablePrivateSubnet, props.publicSubnets, props.privateSubnets);
    this.publicSubnetSelector = {
      subnetType: ec2.SubnetType.PUBLIC
    };

    this.privateSubnetSelector = {
      subnetType: (props.enablePrivateSubnet == true) ? ec2.SubnetType.PRIVATE_ISOLATED : ec2.SubnetType.PRIVATE_WITH_NAT
    };

    this.defaultSecurityGroup = this.createVpcSecurityGroup();

    this.addVpcEndpoints();
  }

  private createVpc(enablePrivateSubnet: boolean, publicMask: number, privateMask: number): ec2.Vpc {
    // Creates vpc with 0 subnets, no IGW, no NatGateway, and default of max 3 
    const vpc = new ec2.Vpc(this, `${this.project}Vpc`, {
      cidr: "10.0.0.0/16",
      subnetConfiguration: [
        {
          cidrMask: publicMask,
          name: "public",
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: privateMask,
          name: (enablePrivateSubnet == true) ? "isolated" : "private",
          subnetType: (enablePrivateSubnet == true) ? ec2.SubnetType.PRIVATE_ISOLATED : ec2.SubnetType.PRIVATE_WITH_NAT,
        }
      ],
      natGateways: (enablePrivateSubnet) ? 0 : 1,
      enableDnsHostnames: true,
      enableDnsSupport: true,

    });
    vpc.selectSubnets(this.publicSubnetSelector).subnets.map(subnet => {
      cdk.Tags.of(subnet).add("kubernetes.io/role/elb", "1");
    });
    vpc.selectSubnets(this.privateSubnetSelector).subnets.map(subnet => {
      cdk.Tags.of(subnet).add("kubernetes.io/role/internal-elb", "1");
    });
    vpc.selectSubnets().subnets.map(subnet => {
      cdk.Tags.of(subnet).add(`kubernetes.io/cluster/${this.clusterName}`, "shared");
    });
    cdk.Tags.of(vpc).add(`kubernetes.io/cluster/${this.clusterName}`, "shared");
    return vpc;
  }

  private createVpcSecurityGroup(): ec2.SecurityGroup {
    // Using a lookup for default security group generated w vpc throws error, create new 'default' security group
    const securityGroup = new ec2.SecurityGroup(this, "htc-grid-vpc-default-security-group", {
      vpc: this.vpc,
    });
    securityGroup.addIngressRule(ec2.Peer.ipv4(this.vpc.vpcCidrBlock), ec2.Port.tcp(443));
    return securityGroup;
  }

  private addVpcEndpoints() {
    // If enabling private subnets, add endpoints
    this.vpc.addGatewayEndpoint("dynamodb-endpoint", {
      service: ec2.GatewayVpcEndpointAwsService.DYNAMODB,
      subnets: [this.privateSubnetSelector],
    });
    this.vpc.addGatewayEndpoint("s3-endpoint", {
      service: ec2.GatewayVpcEndpointAwsService.S3,
      subnets: [this.privateSubnetSelector],
    });
    this.vpc.addInterfaceEndpoint("sqs-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.SQS,
      privateDnsEnabled: true,
      subnets: this.privateSubnetSelector,
      securityGroups: [this.defaultSecurityGroup],
    });
    // CDK does not have a clean built-in autoscaling endpoint, need to manually add
    const autoscaling = `com.amazonaws.${this.region}.autoscaling`;
    new ec2.InterfaceVpcEndpoint(this, "autoscaling-endpoint", {
      vpc: this.vpc,
      service: new ec2.InterfaceVpcEndpointService(autoscaling, 443),
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector,
    });
    this.vpc.addInterfaceEndpoint("ec2-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.EC2,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector,

    });
    this.vpc.addInterfaceEndpoint("ecr-dkr-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
    this.vpc.addInterfaceEndpoint("ecr-api-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.ECR,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
    this.vpc.addInterfaceEndpoint("cw-monitoring-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
    this.vpc.addInterfaceEndpoint("cw-logs-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
    this.vpc.addInterfaceEndpoint("elb-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.ELASTIC_LOAD_BALANCING,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
    this.vpc.addInterfaceEndpoint("api-gw-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.APIGATEWAY,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
    this.vpc.addInterfaceEndpoint("ssm-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.SSM,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
    this.vpc.addInterfaceEndpoint("ssm-messages-endpoint", {
      service: ec2.InterfaceVpcEndpointAwsService.SSM_MESSAGES,
      privateDnsEnabled: true,
      securityGroups: [this.defaultSecurityGroup],
      subnets: this.privateSubnetSelector
    });
  }
}
