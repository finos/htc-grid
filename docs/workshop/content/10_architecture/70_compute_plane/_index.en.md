+++
title = "Compute Plane"
weight = 70
+++

{{% notice note %}}
While the intention of HTC-Grid blueprint is to be modular and provide a flexible integration of modules, we selected EKS as the first and example implementation. However the intent of the blueprint and the project, is to over time integrate with other compute planes and make the optional which control plane is selected according to the workload needs.
{{% /notice %}}

HTC-Grid utilises Amazon Elastic Kubernetes Service (Amazon EKS) as a computational backend. Each engine is a pod containing two containers an Agent and a Lambda. The Lambda container executes lambda locally within the container (there are no calls made to AWS lambda service, the execution is done within the node Lambda container)

EKS service configured with the default [Horizontal Pod Autoscaler](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/).

{{< img "compute-plane-eks.png"  "HTC-compute-plane-eks" >}}

As HTC-Agents are treated as a [Kubernetes deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), a fixed number of pods that will be guaranteed to run on an inactive cluster. Scaling behaviour is then controlled by the auto scaling lambda which regularly checks the depth of the task queue and triggers the appropriate adjustment to the number of nodes. The CloudWatch Adapter  exposes a Kubernetes API so the HPA can access metrics stored in Cloud Watch by the auto scaling Lambda. The Pod Autoscaler (using HPA) adds/removes pods based on these Cloud Watch metrics. Finally, the Node Autoscaler  , adds/removes EC2 instances based on the resource reservation or usage.

{{< img "scale-up-pods.png"  "scale-up-pods" >}}

The corresponding scale down procedure is shown in Figure 4. Pod scale down is triggered when metrics imply a target cluster size that is smaller than the current cluster size. In response, the Kubernetes control plane sends a SIGTERM signal  to selected containers/pods. The SIGTERM is intercepted by the agent, so providing the opportunity to finish the current task and exit gracefully. The pod terminates after the agent exits, or once the terminationGracePeriod has expired . Instance scale down then occurs targeting the removal of inactive instances.

{{< img "scale-down-pods.png"  "scale-down-pods" >}}
