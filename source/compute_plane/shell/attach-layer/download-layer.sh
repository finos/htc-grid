#!/bin/bash

# Copyright 2024 Amazon.com, Inc. or its affiliates. 
# SPDX-License-Identifier: Apache-2.0
# Licensed under the Apache License, Version 2.0 https://aws.amazon.com/apache-2-0/

LAYER_NAME=
LAYER_VERSION=
REGION="eu-west-1"
DESTINATION="."
STORAGE=
S3_LOCATION=

usage () {
    cat <<HELP_USAGE

    $0 -l <string> -v <integer> -r <string> -d <folder>

   -l or --layer       : name of the layer to download
   -v or --version     : version of the layer to download
   -r or --region      : AWS region where layer is stored (default is "eu-west-1")
   -d or --destination : location where to download the layer (default is ".")
   --storage           : "Layer" or "S3"
   -s or --s3          : s3 location, used for internet access is denied

HELP_USAGE
}

echo "starting"
echo $#

while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        -l|--layer)
        LAYER_NAME="$2"
        shift # past argument
        shift # past value
        ;;
        -v|--version)
        LAYER_VERSION="$2"
        shift # past argument
        shift # past value
        ;;
        -r|--region)
        REGION="$2"
        shift # past argument
        shift # past value
        ;;
        -d|--destination)
        DESTINATION="$2"
        shift # past argument
        shift # past value
        ;;
        --storage)
        STORAGE="$2"
        shift # past argument
        shift # past value
        ;;
        -s|--s3)
        S3_LOCATION="$2"
        shift # past argument
        shift # past value
        ;;
        *)    # unknown option
        echo "unprocessed argument: $key"
        usage
        exit 1
        shift # past argument
        ;;
    esac
done

if [ -z $STORAGE ]
then 
    echo "please mention storage type --storage"
    usage
    exit 2
fi

if ! mkdir -p $DESTINATION
then
    echo "failed while creating the destionation folder"
    echo "mkdir -p $DESTINATION"
    exit 4
fi

if ! cd $DESTINATION
then
    echo "cannot cd into the destination folder"
    echo "cd $DESTINATION"
    exit 5
fi

if [ $STORAGE == "Layer" ]
then
    if [ -z $LAYER_NAME ]
    then
        echo "Layer name is empty, please use -l/--layer to provide a layer name"
        usage
        exit 2
    fi

    if [ -z $LAYER_VERSION ]
    then
        echo "Layer version is empty, please use -v/--version to provide a version layer"
        usage
        exit 3
    fi

    echo "aws lambda get-layer-version --region $REGION --version-number $LAYER_VERSION --layer-name $LAYER_NAME --query Content.Location --output text"

    if ! url=$(aws lambda get-layer-version --region $REGION --version-number $LAYER_VERSION --layer-name $LAYER_NAME --query Content.Location --output text)
    then
        echo "failed while getting the URL for download"
        echo "aws lambda get-layer-version --region $REGION --version-number $LAYER_VERSION --layer-name $LAYER_NAME --query Content.Location --output text"
        exit 6
    fi

    if ! curl -o layer.zip $url
    then
        echo "failed while downloading the layer"
        echo "curl -o layer.zip $url"
        exit 7
    fi
else
    if [ -z $S3_LOCATION ]
    then
        echo "s3 location is empty, please use -s/--s3 to provide a s3 location"
        usage
        exit 8
    fi
    if ! aws s3 cp $S3_LOCATION ./layer.zip
    then
        echo "failed while downloading the binaries from s3 location"
        usage
        exit 9
    fi
fi

if ! unzip -o layer.zip
then
    echo "failed while unzipping the layer"
    echo "curl -o layer.zip $url"
    exit 8
fi

