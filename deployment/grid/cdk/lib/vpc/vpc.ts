//vpc.ts
import { Construct } from "constructs";
import * as cdk from "aws-cdk-lib"

import {
  InterfaceVpcEndpoint,
  InterfaceVpcEndpointService,
  InterfaceVpcEndpointAwsService,
  GatewayVpcEndpointAwsService,
  Peer,
  PrivateSubnet,
  PublicSubnet,
  Port,
  SecurityGroup,
  ISecurityGroup,
  Vpc,
  IVpc,
  CfnNatGateway,
  CfnVPCGatewayAttachment,
  CfnInternetGateway,
} from "aws-cdk-lib/aws-ec2";


export interface VpcStackProps extends cdk.StackProps {

  project: string ;
  clusterName: string ;

  publicSubnets:string[] ;
  privateSubnets:string[] ;
  enablePrivateSubnet:string;

}
export class VpcStack extends cdk.Stack {
  public readonly vpc: IVpc;
  public readonly defaultSecurityGroup: ISecurityGroup;

  private subnetNumber = 1;
  private natGateway: CfnNatGateway | undefined;
  private project
  private clusterName
  private publicSubnets
  private privateSubnets
  private enablePrivateSubnet


  get availabilityZones(): string[] {
    return [cdk.Fn.select(0, cdk.Fn.getAzs()), cdk.Fn.select(1, cdk.Fn.getAzs())];
  }
  constructor(scope: Construct, id: string, props: VpcStackProps) {
    super(scope, id, props);

    this.project = props.project
    this.clusterName = props.clusterName
    this.publicSubnets = props.publicSubnets
    this.privateSubnets = props.privateSubnets
    this.enablePrivateSubnet= props.enablePrivateSubnet

    this.vpc = this.createVpc();

    this.defaultSecurityGroup = this.createVpcSecurityGroup();

    this.createVpcSubnets();

    this.addVpcEndpoints();
  }
  private createVpc(): Vpc {
    // Creates vpc with 0 subnets, no IGW, no NatGateway, and default of max 3 AZs
    const vpc = new Vpc(this, `${this.project}Vpc`, {
      cidr: "10.0.0.0/16",
      subnetConfiguration: [],
      natGateways: 0,
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
    cdk.Tags.of(vpc).add(`kubernetes.io/cluster/${this.clusterName}`, "shared");
    return vpc;
  }
  private createVpcSecurityGroup(): SecurityGroup {
    // Using a lookup for default security group generated w vpc throws error, create new 'default' security group
    return new SecurityGroup(this, "htc-grid-vpc-default-security-group", {
      vpc: this.vpc,
    });
  }
  private createVpcSubnets() {
    this.createVpcPublicSubnets();
    this.createVpcPrivateSubnets();
  }
  private createVpcPublicSubnets() {
    // Create IGW & associate with vpc
    const igw = new CfnInternetGateway(this, "IGW", {});
    const internet_gateway = new CfnVPCGatewayAttachment(this, "VPC-IGW", {
      internetGatewayId: igw.ref,
      vpcId: this.vpc.vpcId,
    });
    var az = 0;
    this.publicSubnets.forEach((cidr: string) => {
      let pub_subnet = new PublicSubnet(
        this,
        `${this.project} Subnet ${this.subnetNumber}`,
        {
          availabilityZone: this.vpc.availabilityZones[az],
          cidrBlock: cidr,
          vpcId: this.vpc.vpcId,
          mapPublicIpOnLaunch: true,
        }
      );
      this.subnetNumber++;
      pub_subnet.addDefaultInternetRoute(igw.ref, internet_gateway);
      if (this.natGateway === undefined && this.enablePrivateSubnet) {
        this.natGateway = pub_subnet.addNatGateway();
      }
      // Iterate each az, adding subnets, until at the last az
      if (az < this.vpc.availabilityZones.length - 1) {
        az++;
      }
      this.defaultSecurityGroup.addIngressRule(Peer.ipv4(cidr), Port.tcp(443));
      this.vpc.publicSubnets.push(pub_subnet);
      cdk.Tags.of(pub_subnet).add(
        `kubernetes.io/cluster/${this.clusterName}`,
        "shared"
      );
      cdk.Tags.of(pub_subnet).add("kubernetes.io/role/elb", "1");
    });
  }
  private createVpcPrivateSubnets() {
    var az = 0;
    this.privateSubnets.forEach((cidr: string) => {
      let priv_subnet = new PrivateSubnet(
        this,
        `${this.project} Subnet ${this.subnetNumber}`,
        {
          availabilityZone: this.vpc.availabilityZones[az],
          cidrBlock: cidr,
          vpcId: this.vpc.vpcId,
          mapPublicIpOnLaunch: false,
        }
      );
      this.subnetNumber++;
      if (this.natGateway !== undefined) {
        priv_subnet.addDefaultNatRoute(this.natGateway.ref);
      }
      if (az < this.vpc.availabilityZones.length - 1) {
        az++;
      }
      this.defaultSecurityGroup.addIngressRule(Peer.ipv4(cidr), Port.tcp(443));
      this.vpc.privateSubnets.push(priv_subnet);
      cdk.Tags.of(priv_subnet).add(
        `kubernetes.io/cluster/${this.clusterName}`,
        "shared"
      );
      cdk.Tags.of(priv_subnet).add("kubernetes.io/role/internal-elb", "1");
    });
  }
  private addVpcEndpoints() {
    // If enabling private subnets, add endpoints
    if (this.enablePrivateSubnet) {
      this.vpc.addGatewayEndpoint("dynamodb-endpoint", {
        service: GatewayVpcEndpointAwsService.DYNAMODB,
      });
      this.vpc.addGatewayEndpoint("s3-endpoint", {
        service: GatewayVpcEndpointAwsService.S3,
      });
      this.vpc.addInterfaceEndpoint("sqs-endpoint", {
        service: InterfaceVpcEndpointAwsService.SQS,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      // CDK does not have a clean built-in autoscaling endpoint, need to manually add
      const autoscaling = `com.amazonaws.${this.region}.autoscaling`;
      new InterfaceVpcEndpoint(this, "autoscaling-endpoint", {
        vpc: this.vpc,
        service: new InterfaceVpcEndpointService(autoscaling, 443),
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("ec2-endpoint", {
        service: InterfaceVpcEndpointAwsService.EC2,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("ecr-dkr-endpoint", {
        service: InterfaceVpcEndpointAwsService.ECR_DOCKER,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("ecr-api-endpoint", {
        service: InterfaceVpcEndpointAwsService.ECR,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("cw-monitoring-endpoint", {
        service: InterfaceVpcEndpointAwsService.CLOUDWATCH,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("cw-logs-endpoint", {
        service: InterfaceVpcEndpointAwsService.CLOUDWATCH_LOGS,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("elb-endpoint", {
        service: InterfaceVpcEndpointAwsService.ELASTIC_LOAD_BALANCING,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("api-gw-endpoint", {
        service: InterfaceVpcEndpointAwsService.APIGATEWAY,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("ssm-endpoint", {
        service: InterfaceVpcEndpointAwsService.SSM,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
      this.vpc.addInterfaceEndpoint("ssm-messages-endpoint", {
        service: InterfaceVpcEndpointAwsService.SSM_MESSAGES,
        privateDnsEnabled: true,
        securityGroups: [this.defaultSecurityGroup],
      });
    }
  }
}
