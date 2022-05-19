
### Current
grid
  * terraform
    * compute_plane
    * control_plane
    * htc-agent
    * vpc

### EKS (Claudiu)
grid
  * terraform
    * compute_plane
      * eks
      * ecs
      * scaling_lambda
    * control_plane
    * htc_agent
      * ecs
      * eks
    * vpc
### Main Structure (Terraform and file)
* grid
  * terraform
    * compute_plane
      * ecs (compute only)
        * augmented configuration 
        * htc-agent
          * side-car container cloud-watch , xray agent
          * agent+ lambda as side-car 
          * ecs service
        * cluster
          * scaling policy
        * logging
        * monitoring on ecs
          * dashboard (json)
          * timestreamDB
          * AMP
          * AMG
      * eks (compute only)
        * augmented configuration
        * htc-agent
          * side car container 
          * agent+ lambda as side-car
        * cluster (published third parties module)
          * hpa
        * logging
        * charts
        * monitoring solution
          * hosted inlfuxdb
          * promethues
          * grafana
          * grafana_auth
      * custom_compute 
      * scaling_lambda
      * global-auth
    * control_plane+data_plane
    * vpc


    
variables:
    * create = true 


Optional    
##
* terraform:
  * modules/
    * compute_plane
      * 
    * control_plane+data_plane
    * vpc
  * grid
    * main.tf
    * variables.tf
    * ouputs.tf