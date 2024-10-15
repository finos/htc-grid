---
title: "Prerequisites"
chapter: false
weight: 40
---

## Python

The current release of HTC requires python3.7, and the documentation assumes the use of virtualenv. Set this up as follows:

```
cd htc-grid
virtualenv venv
```

This will create a virtual environment for python execution with dependencies and libraries required. To activate the environment run:

```
source ./venv/bin/activate
echo "source ~/environment/htc-grid/venv/bin/activate" >> ~/.bashrc
```

To validate the version of python we are using is the one from the virtual environment we just created you can run, and it should point to `~/environment/htc-grid/venv/bin/python`

```
which python
```

## Define Environment Variables for deploying the Infrastructure

To simplify the deployment we will use a set of environment variables, that later on we will be able to use and replace in multiple commands. We will also store this environment variables in a `load_variables.sh` file that we will be able to use to reload them whenever we need them (for example,when opening multiple terminals in Cloud9 IDE).


```
export TAG=main
export HTCGRID_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

for var in TAG HTCGRID_REGION  ; do echo "export $var=$(eval "echo \"\$$var\"")" >> load_variables.sh ; done
echo -e "===\nYour variables and configuration have been setup as follows\n===\n$(cat load_variables.sh)"
echo "source ~/environment/htc-grid/load_variables.sh" >> ~/.bashrc
```

The code above first set the variables and then, saves all of them within the file `load_variables.sh` file. Finally it creates a line within the `bashrc` file so that whenever we create new terminal the variables get pre-loaded.

As for the variables that we have created: 

* **TAG**: HTC-Grid can be deployed many times per account. We however must clearly define each setup using a TAG.  We've used `main` as the TAG for our setup. TAG will be used in the naming of the S3 buckets, so it needs to follow S3 naming rules.
* **HTCGRID_REGION** The region where we are installing HTC-Grid.

## Create the infrastructure for storing the state of the HTC Grid

The following step creates 3 S3 buckets that will be needed during the installation:
* 2 buckets will store the state of the different terraform deployments
* 1 bucket will store the HTC artifacts (the lambda to be executed by the agent)

```
make init-grid-state TAG=$TAG REGION=$HTCGRID_REGION
```

To validate the creation of the S3 buckets, you can run

```
aws cloudformation describe-stacks --stack-name $TAG --region $HTCGRID_REGION --query 'Stacks[0]'
```

That will list the 3 S3 Buckets that we just created.
