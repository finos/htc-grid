---
title: "Configure your Workspace"
chapter: false
weight: 30
---

## Accessing Cloud9 Workspace

Go to the **Cloud9** console and select the workspace that was created for this workshop. When running at an AWS event it will come up with a name such as **mod-XXXXXXXXXXXXXXXX**. Click on **Open IDE**

{{< img "cloud9_open_ide.png" "Cloud9 Open IDE" >}}

Once in you should get the familiar look and feel of IDE's. With a file navigation panel on your left hand side, an Editor on the top right panel and a terminal on the bottom right panel. We will use the terminal and in some cases the editor.


{{% notice info %}}
Cloud9 normally manages IAM credentials dynamically. This isn't currently compatible with
the EKS IAM authentication, so we will disable it and rely on the IAM role instead.
{{% /notice %}}

## Configuring Workspaces credentials

Disabling Cloud9 managed credentials can be achieved using the following point and click steps, or running the command further below.

- Return to your workspace and click the sprocket, or launch a new tab to open the Preferences tab
- Select **AWS SETTINGS**
- Turn off **AWS managed temporary credentials**
- Close the Preferences tab

{{< img "c9disableiam.png" "Disable Cloud9 IAM">}}

The above can easily be achieved by running this command in your Cloud9 terminal:
```
aws cloud9 update-environment --environment-id ${C9_PID} --managed-credentials-action DISABLE
```

To ensure that we don't use any temporary credentials, we will also remove any existing credentials file:
```
rm -vf ${HOME}/.aws/credentials
```

### Validate the IAM role {#validate_iam}

Use the [GetCallerIdentity](https://docs.aws.amazon.com/cli/latest/reference/sts/get-caller-identity.html) CLI command to validate that the Cloud9 IDE is using the correct IAM role.

```
aws sts get-caller-identity
```


#### Validating the IAM Role when running at an AWS event

The output assumed-role name should contain:
```
TeamRole
```
If the _Arn_ contains the role name from above and an Instance ID, you may proceed.

```output
{
    "Account": "123456789012", 
    "UserId": "AROA1SAMPLEAWSIAMROLE:i-01234567890abcdef", 
    "Arn": "arn:aws:sts::216876048363:assumed-role/TeamRole/i-0dd09eac19be01448"
}
```

#### Validating the IAM Role when running on your own

The output assumed-role name should contain the name you chose for your CloudFormation stack at the [Deploying Cloud9 Workspace]({{< ref "20_deploy_htc/10_self_paced/_index.en.md#deploying-cloud9-workspace" >}}) section:
```
htc-grid-workshop
```

If the _Arn_ contains the role name from above and an Instance ID, you may proceed.

```output
{
    "Account": "123456789012", 
    "UserId": "AROA1SAMPLEAWSIAMROLE:i-01234567890abcdef", 
    "Arn": "arn:aws:sts::123456789012:assumed-role/htc-grid-workshop-C9Role-XXXXXXXXXXXXXXXX/i-01234567890abcdef"
}
```
