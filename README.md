[![FINOS - Incubating](https://cdn.jsdelivr.net/gh/finos/contrib-toolbox@master/images/badge-incubating.svg)](https://community.finos.org/docs/governance/Software-Projects/stages/incubating)

# HTC-Grid
The high throughput compute grid project (HTC-Grid) is a container based cloud native HPC/Grid environment. The project provides a reference architecture that can be used to build and adapt a modern High throughput compute solution using underlying AWS services, allowing users to submit high volumes of short and long running tasks and scaling environments dynamically.

**Warning**: This project is an Open Source (Apache 2.0 License), not a supported AWS Service offering.

### When should I use HTC-Grid ?
HTC-Grid should be used when the following criteria are meet:
1. A high task throughput is required (from 250 to 30,000+ tasks per second).
2. The tasks are loosely coupled.
3. Variable workloads (tasks with heterogeneous execution times) are expected and the solution needs to dynamically scale with the load.

### When should I not use the HTC-Grid ?
HTC-Grid might not be the best choice if :
1. The required task throughput is below 250 tasks per second: Use [AWS Batch](https://aws.amazon.com/batch/) instead.
2. The tasks are tightly coupled, or use MPI. Consider using either [AWS Parallel Cluster](https://aws.amazon.com/hpc/parallelcluster/) or [AWS Batch Multi-Node workloads](https://docs.aws.amazon.com/batch/latest/userguide/multi-node-parallel-jobs.html) instead
3. The tasks uses third party licensed software.

### How do I use HTC-Grid ?

The full documentation of the HTC grid can be accessed here [https://finos.github.io/htc-grid/](https://finos.github.io/htc-grid/)

## Contributing

For any questions, bugs or feature requests please open an [issue](https://github.com/finos/htc-grid/issues).

To submit a contribution:
1. Fork it (<https://github.com/finos/htc-grid/fork>)
2. Create your feature branch (`git checkout -b feature/fooBar`)
3. Read our [contribution guidelines](.github/CONTRIBUTING.md) and [Community Code of Conduct](https://www.finos.org/code-of-conduct)
4. Commit your changes (`git commit -am 'Add some fooBar'`)
5. Push to the branch (`git push origin feature/fooBar`)
6. Create a new Pull Request

_NOTE:_ Commits and pull requests to FINOS repositories will only be accepted from those contributors with an active, executed Individual Contributor License Agreement (ICLA) with FINOS OR who are covered under an existing and active Corporate Contribution License Agreement (CCLA) executed with FINOS. Commits from individuals not covered under an ICLA or CCLA will be flagged and blocked by [EasyCLA](https://community.finos.org/docs/governance/Software-Projects/easycla). Please note that some CCLAs require individuals/employees to be explicitly named on the CCLA.

*Need an ICLA? Unsure if you are covered under an existing CCLA? Email [help@finos.org](mailto:help@finos.org)*

## License

Copyright 2024 Amazon.com, Inc. or its affiliates

Distributed under the [Apache License, Version 2.0](http://www.apache.org/licenses/LICENSE-2.0).

SPDX-License-Identifier: [Apache-2.0](https://spdx.org/licenses/Apache-2.0)


