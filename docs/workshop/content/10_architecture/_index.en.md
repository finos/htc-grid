+++
title = "Architecture"
chapter = false
weight = 10
pre = "<b>1. </b>"
+++

This section outlines the high level modular architecture of the cloud native HTC-Grid and the Tenets used when designing HTC-Grid.

### HTC-Grid Tenets

HTC-Grid’s design tenets have been moulded by the requirements of early adopters and by recurring themes observed in Grid computing .

1.	**Scale, high-throughput**: To meet the most demanding of FSI risk environments - achieve a provisioning capacity of >100,000’s cores across multiple AWS regions; 
1.	**Low Latency**: Support sustained compute task throughput of >10,000TPS and ensure low infrastructure latency (~0.1s) to efficiently support short duration tasks (~1s) without batching.
1.	**On-Demand**: The ability to created & dedicated services on-demand: e.g., for overnight batch workloads; or for volatile intra-day workloads align to specific trading desks or individual power users.
1.	**Modular**: Not all workloads have the same requirements and may benefit from different infrastructure performance/costs optimizations; hence a composable extensible architecture is required. This is enabled via interchangeable implementations of the data- and compute-planes: through composability of the modular deployment descriptor (Infrastructure as Code).
1.	**Simplify re-Platforming**: Support client APIs that are familiar to AWS customers.
1.	**All compute looks like lambda**: Tasks API’s are lambdas irrespective of the backend compute resource (Lambda Service, Container or EC2) being used.
1.	**Cloud-native**: Fully leverage operationally hardened AWS core services to optimize robustness and performance while minimizing operational management.

