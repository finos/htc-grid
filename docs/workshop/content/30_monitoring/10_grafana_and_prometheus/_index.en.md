---
title: "Grafana and Prometheus"
chapter: false
weight: 10
---

HTC-Grid blueprint deploys Grafana and Prometheus as Pods within the EKS Cluster (in this case using On-Demand instances, given this services are expected to have a state / VolumeSet).

{{% notice note %}}
While the deployment of Grafana uses self-signed certifictes for encryption, our end plan for HTC-Grid is to adhere to the tenets. We are planning to move over to [Amazon Managed Service for Prometheus](https://aws.amazon.com/prometheus/) (currently in preview) and [Amazon Managed Service for Grafana](https://aws.amazon.com/grafana/). 
{{% /notice %}}


## Create a cognito user (CLI)
All the services behind a public URL are protected wih an authentication mecanism based on Cognito. So in order to acccess the grafana dashboard you will need to create a cognito user.
Please from the root of the project :
Choose a cognito username:
```bash
export USERNAME=<my_cognito_user>
```
Choose a cognito password (make this password follows [cognito default policy](https://docs.aws.amazon.com/cognito/latest/developerguide/user-pool-settings-policies.html) ) :
You can reuse the password chosen  in section [Deploy HTC-Grid]({{< ref "20_deploy_htc/80_deploying_htc/_index.en.md" >}}) or create a new one.
```bash
export PASSWORD=<my_grafana_admin_password>
```

Get the client id:
```bash
clientid=$(make get-client-id  TAG=$TAG)
```

Create the user
```bash
aws cognito-idp sign-up --region $HTCGRID_REGION --client-id $clientid --username $USERNAME --password $PASSWORD
```
The user newly created will be unconfirmed.

Confirm user creation:
```bash
aws cognito-idp admin-confirm-sign-up --region $HTCGRID_REGION --user-pool-id $userpoolid --username $USERNAME
```
## Grafana

During the [Deploy HTC-Grid]({{< ref "20_deploy_htc/80_deploying_htc/_index.en.md" >}}) section you replaced and selected a **<my_grafana_admin_password>** that we will need now to access grafana. The HTC-Grid project captures metrics into influxdb and prometheus and exposes those metrics through Grafana. 

To find out the https endpoint where grafana has been deployed type:

```
kubectl -n grafana get ingress | tail -n 1 | awk '{ print "Grafana URL  -> https://"$4 }'
```

it should output something like:

```
Grafana URL  -> https://k8s-grafana-grafanai-XXXXXXXXXXXX-YYYYYYYYYYY.eu-west-2.elb.amazonaws.com
```

If you open this URL you will be redirected to a cognito sign in page. Please enter the username and password created in the previous section.
Once you are sign up  with cognito you will be redirected to the Grafana sign in page.

Pleas use the user `admin` and the password you selected at creation time to login into Grafana.

Once in, on the left hand side menu, click on **Dashboards** and then select **Manage**. This will take you to the two dashboards that have been created at this stage. One for the EKS Cluster and another one with a few metrics relevant to HTC-Grid components. 

{{< img "grafana_dashboards.png" "Grafana Dashboards" >}}

At this stage most of the dashboards will be nearly empty of data as we just have submitted a single task. Later on, as we create more tasks, we will be able to see how this dashboards represent the workloads running on HTC-Grid

{{< img "grafana_single_task.png" "Grafana Single task" >}}


## Prometheus 

Prometheus is other of the services used to store time series for the EKS cluster. In order to access the Prometheus server URL, we are going to use the kubectl port-forward command to access the application. In Cloud9, open a new terminal and run:

```
kubectl port-forward -n prometheus deploy/prometheus-server 8080:9090
```

Leave the terminal running. Then in your Cloud9 environment, click **Tools** / **Preview** / **Preview Running Application**.  This will show a preview in a new IDE windows side by side with the terminal. You can click on the icon on the side of the **Browser** to pop up the preview to another window.

{{< img "prometheus_preview.png" "prometheus_preview" >}}

Prometheus has a set of targets that it takes metrics from using. You can check the targets by clicking on the **Status** / **Apiserver** 


