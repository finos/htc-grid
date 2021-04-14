# Managing HTC-Grid after deployment
## Managing the HTC-Grid agent
1. Make connection with EKS, go in the [deployment/grid/terraform](deployment/grid/terraform) folder where terraform apply has been run. Then make sure that KUBECONFIG is set (see step 6).
2. Set up the storage for helm
    ```bash
    export HELM_DRIVER=configmap
    ```

2. Deploy the agent

    ```bash
    helm install <your release name> ../charts/agent-htc-lambda --set fullnameOverride=htc-agent
    ```

3. Test the installation by running

    ```bash
    helm test <your release name>
    ```

4. Delete the agent

    ```bash
    helm uninstall <your release name>
    ```

5. Get deployed pods ( see notes after agent deployment )
6. Get the log of a pod: (  see notes after agent deployment )
7. Describe the state of a pod , useful for debugging situation never run, (see notes after agent deployment)
8. Execute a command into a pod

    ``` bash
    kubectl exec  <pod name> -c <container name> <command>
    ```

9. Open an interactive session into a pod

    ```bash
    kubectl exec -it <pod name> bash
    ```

10. Get config-map used in the pods, i.e., current configuration

    ```bash
    kubectl get cm agent-configmap -o yaml
    ```

11. Get information about the pod autoscaler

    ```bash
    kubectl get hpa
    kubectl get hpa -w
    ```

* Updating number of replicas (my_cluster is your release name that you selected with helm)

```
helm upgrade --set replicaCount=5 --set foo=newbar my_cluster ./agent-htc-lambda
```

##  Common commands

* Get logs from a running agent and lambda worker

    ```bash
    kubectl logs -c <agent or lambda> <pod name>

    Examples:
    kubectl logs -c agent htc-agent-544bd95456-wgzqs

    kubectl logs -c lambda htc-agent-544bd95456-wgzqs
    ```


* Launching Tests

    ```bash
    cd root/examples/submissions/k8s_jobs
    kubectl apply -f <test-name.yaml>

    example:
    kubectl apply -f scaling-test.yaml

    Follow the execution of the test
    kubectl logs job/scaling-test -f
    ```

* Deleting all running pods

    ```bash
    kubectl delete $(kubectl get po -o name)
    ```
