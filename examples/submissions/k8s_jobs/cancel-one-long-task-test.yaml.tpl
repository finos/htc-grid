apiVersion: batch/v1
kind: Job
metadata:
  name: test-cancel-one-long-task
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
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
        command: ["python3","./cancel_tasks.py", "--test_cancel_one_long_task", "1"]
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
