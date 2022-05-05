import json
import logging

from apply import apply_handler
from helm import helm_handler
from custom import custom_handler

def handler(event, context):
  print(json.dumps(event))

  resource_type = event['ResourceType']
  if resource_type == 'Custom::ClusterManagerPlus-Apply':
    return apply_handler(event, context)

  if resource_type == 'Custom::ClusterManagerPlus-HelmChart':
    return helm_handler(event, context)

  if resource_type == 'Custom::ClusterManagerPlus-Custom':
    return custom_handler(event, context)

  raise Exception("unknown resource type %s" % resource_type)
