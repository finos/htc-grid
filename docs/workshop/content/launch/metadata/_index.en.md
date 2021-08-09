+++
title = "Metadata"
description = "Use metadata to catalogue and describe your workshop"
weight = 51
+++

There is a `metadata.yml` file found in the root of this repository that allows workshop creators to store descriptive information about their content for discovery & identification purposes.

{{% notice note %}}
A `metadata.yml` file is required for all workshops that are intended to be reused and shared broadly.
{{% /notice %}}

```yaml
#name - DNS-friendly name for the workshop. This will be used when generating the hosting URL (ie. https://my-first-workshop.workshops.aws/)
name: my-first-workshop
#title - The title of your workshop
title: My First Workshop 
#description - A short description that will be displayed in search results
description: Creating unicorns with serverless bitcoin magic! 
#categories - Refer to official AWS categories covered by the workshop content here
categories: 
  - Networking
  - Compute
#services - Refer to the official AWS service names covered by the workshop content here
services: 
   - Api Gateway
   - Lambda
#level - Approximate skill level needed for this workshop
level: 100 
#duration - Estimated duration in minutes
duration: 60 
#cost - Cost in USD. If the content is offered without cost, enter 0
cost: 0 
#author - Amazon alias of the primary author of the content
author: mpgoetz 
#audience - Names of the personas associated with this workshop
audience: 
  - IT Professional
  - Developer
```