apiVersion: batch/v1
kind: Job
metadata:
  name: single-task
spec:
  template:
    spec:
      containers:
      - name: generator
        securityContext:
            {}
        image: {{account_id}}.dkr.ecr.{{region}}.amazonaws.com/{{image_name}}:{{image_tag}}
        imagePullPolicy: Always
        resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
        command: ["python3","./client.py", "-n", "1",  "--worker_arguments", "1000 1 1","--job_size","1","--job_batch_size","1","--log","warning"]
        volumeMounts:
          - name: agent-config-volume
            mountPath: /etc/agent
        env:
          - name: INTRA_VPC
            value: "1"
      restartPolicy: Never
      nodeSelector:
        grid/type: Operator
      tolerations:
      - effect: NoSchedule
        key: grid/type
        operator: Equal
        value: Operator
      volumes:
        - name: agent-config-volume
          configMap:
            name: agent-configmap
  backoffLimit: 0
