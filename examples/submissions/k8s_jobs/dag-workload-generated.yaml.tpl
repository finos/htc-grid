apiVersion: batch/v1
kind: Job
metadata:
  name: dag-workload-generated
  annotations:
    seccomp.security.alpha.kubernetes.io/pod: "runtime/default"
spec:
  template:
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: generator
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault
          capabilities:
            drop:
            - NET_RAW
            - ALL
        image: {{account_id}}.dkr.ecr.{{region}}.amazonaws.com/{{image_name}}:{{image_tag}}
        imagePullPolicy: Always
        resources:
            limits:
              cpu: 8000m
              memory: 12000Mi
            requests:
              cpu: 8000m
              memory: 12000Mi
        command: ["python3", "./dag_client.py", "--generate", "--depth", "3", "--breadth", "2"]
        volumeMounts:
          - name: agent-config-volume
            mountPath: /etc/agent
        env:
          - name: INTRA_VPC
            value: "1"
      restartPolicy: Never
      nodeSelector:
        htc/node-type: core
      tolerations:
      - effect: NoSchedule
        key: htc/node-type
        operator: Equal
        value: core
      volumes:
        - name: agent-config-volume
          configMap:
            name: agent-configmap
  backoffLimit: 0
