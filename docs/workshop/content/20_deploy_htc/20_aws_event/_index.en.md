---
title: "...at an AWS event"
chapter: false
weight: 20
---

### Running the workshop at an AWS Event

{{% notice warning %}}
Only complete this section if you are at an AWS hosted event (such as AWS Lofts, Immersion Day, or any other event hosted by an AWS employee). If you are running the workshop on your own, go to: [Start the workshop on your own]({{< ref "20_deploy_htc/20_aws_event/_index.en.md" >}}).
{{% /notice %}}

### Login to the AWS Workshop Portal

If you are at an AWS event, an AWS account was created for you to use throughout the workshop. You will need the **Participant Hash** provided to you by the event's organizers.

1. Connect to the portal by browsing to [https://dashboard.eventengine.run/](https://dashboard.eventengine.run/).
2. Enter the Hash in the text box, and click **Proceed** 
3. In the User Dashboard screen, click **AWS Console** 
4. In the popup page, click **Open Console** 

You are now logged in to the AWS console in an account that was created for you, and will be available only throughout the workshop run time.

{{% notice info %}}
In the interest of time, for the event we have pre-deployed a set of resources for you, starting with a Cloud9 environment that you can use to run the workshop. The [Cloud9 Environment is available here](https://github.com/finos/htc-grid/blob/main/deployment/dev_environment_cloud9/cfn/cloud9-htc-grid.yaml).  In some workshops, this might be extendeed with a few extra command and resulting in skipping a few other sections in the workshop (such us skipping the download and copy of container images). Just follow the instructions at the event. The instructor will point you where to start.
{{% /notice %}}
