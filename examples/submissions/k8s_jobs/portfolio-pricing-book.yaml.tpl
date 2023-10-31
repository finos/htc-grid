apiVersion: batch/v1
kind: Job
metadata:
  name: portfolio-pricing-book
spec:
  template:
    spec:
      containers:
      - name: generator
        securityContext:
          runAsNonRoot: true
          allowPrivilegeEscalation: false
          seccompProfile:
            type: RuntimeDefault
        image: {{account_id}}.dkr.ecr.{{region}}.amazonaws.com/{{image_name}}:{{image_tag}}
        imagePullPolicy: Always
        resources:
            limits:
              cpu: 100m
              memory: 128Mi
            requests:
              cpu: 100m
              memory: 128Mi
        command: ["python3","./portfolio_pricing_client.py", "--workload_type", "random_portfolio", "--portfolio_size", "10", "--trades_per_worker", "1"]
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
