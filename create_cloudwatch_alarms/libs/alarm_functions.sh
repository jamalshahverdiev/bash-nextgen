#!/usr/bin/env bash

configure_alb_alarms() {
  ALB_LIST=($(aws --profile $AWS_PROFILE elbv2 describe-load-balancers | jq -r ".LoadBalancers[].LoadBalancerName"))

  for ALB_NAME in "${ALB_LIST[@]}"; do
      clean_alarms_from_aws 'ApplicationELB' ${ALB_NAME}
      # Load Balancer Low Latency Check, no Latency
      create_alarm_by_object "${ALB_NAME}" 'ApplicationELB' 'Average' 'TargetResponseTime' 'GreaterThanThreshold' '80' '60' '2' '3' \
          "${URGENT_ALARM_ACTION}" 'notBreaching' 'Seconds' && echo "Created alarm: ${name_and_description}"
      # Load Balancer High Latency Check, no Latency
      create_alarm_by_object "${ALB_NAME}" 'ApplicationELB' 'Average' 'TargetResponseTime' 'GreaterThanThreshold' '80' '60' '4' '5' \
          "${URGENT_ALARM_ACTION}" 'notBreaching' 'Seconds' && echo "Created alarm: ${name_and_description}"
      # Target Group of ALB 5XX
      create_alarm_by_object "${ALB_NAME}" 'ApplicationELB' 'Sum' 'HTTPCode_Target_5XX_Count' 'GreaterThanOrEqualToThreshold' '16' '60' '3' '5' \
          "${URGENT_ALARM_ACTION}" 'notBreaching' && echo "Created alarm: ${name_and_description}"
      # Target Group of ALB 4XX
      create_alarm_by_object "${ALB_NAME}" 'ApplicationELB' 'Sum' 'HTTPCode_Target_4XX_Count' 'GreaterThanThreshold' '70' '60' '3' '5' \
          "${ALARM_ACTION}" 'notBreaching' && echo "Created alarm: ${name_and_description}"
      # ALB 5XX count HTTPCode_ELB_5XX_Count 
      create_alarm_by_object "${ALB_NAME}" 'ApplicationELB' 'Sum' 'HTTPCode_ELB_5XX_Count' 'GreaterThanOrEqualToThreshold' '16' '60' '3' '5' \
          "${URGENT_ALARM_ACTION}" 'notBreaching' && echo "Created alarm: ${name_and_description}"
  done
}

# https://docs.aws.amazon.com/cli/latest/reference/ec2/describe-instances.html
configure_ec2_alarms() {
  EC2_MONITOR_TAG="CW_MONITOR"
  echo "EC2 Instance IDs:"
  aws --profile $AWS_PROFILE ec2 describe-instances --filters Name=instance-state-name,Values=running Name=tag-key,Values=$EC2_MONITOR_TAG | jq -r '.Reservations[].Instances[].InstanceId' || exit $?
  EC2_INSTANCE_LIST=($(aws --profile $AWS_PROFILE ec2 describe-instances --filters Name=instance-state-name,Values=running Name=tag-key,Values=$EC2_MONITOR_TAG | jq -r '.Reservations[].Instances[].InstanceId'))
  
  for EC2_INSTANCE_ID in "${EC2_INSTANCE_LIST[@]}"; do
    EC2_INSTANCE_NAME=$(aws --profile $AWS_PROFILE ec2 describe-instances --instance-ids $EC2_INSTANCE_ID | jq -r '.Reservations[].Instances[].Tags[] | select (.Key == "Name") | .Value')
    clean_alarms_from_aws 'EC2' ${EC2_INSTANCE_NAME}
    # Instance CPU Check
    if [[ ${EC2_INSTANCE_NAME} != 'backup-controller-production' ]]; then
        create_alarm_by_object "${EC2_INSTANCE_NAME}" 'EC2' 'Average' 'CPUUtilization' 'GreaterThanThreshold' '90' '120' '2' '3' \
            "${ALARM_ACTION}" '' 'Percent' && echo "Created alarm: ${name_and_description}"        
    fi
    # Instance Status Check
    create_alarm_by_object "${EC2_INSTANCE_NAME}" 'EC2' 'Maximum' 'StatusCheckFailed' 'GreaterThanThreshold' '0' '120' '1' '1' \
        "${ALARM_ACTION}" '' 'Count' && echo "Created alarm: ${name_and_description}"
  done
}

configure_elastisearch_alarms() {
  echo "ES list:"
  aws --profile $AWS_PROFILE es list-domain-names | jq -r '.DomainNames[].DomainName' || exit $?
  ES_LIST=($(aws --profile $AWS_PROFILE es list-domain-names | jq -r '.DomainNames[].DomainName'))
  CLIENT_ID=($(aws --profile $AWS_PROFILE sts get-caller-identity | jq -r '.Account'))

  for ES_NAME in "${ES_LIST[@]}"; do
    clean_alarms_from_aws 'ES' ${ES_NAME}
    # ES metrics to add # https://docs.aws.amazon.com/elasticsearch-service/latest/developerguide/cloudwatch-alarms.html
    create_alarm_by_object "${ES_NAME}" 'ES' 'Maximum' 'ClusterStatus.yellow' 'GreaterThanThreshold' '1' '60' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Count' && echo "Created alarm: ${name_and_description}"
    create_alarm_by_object "${ES_NAME}" 'ES' 'Maximum' 'ClusterStatus.red' 'GreaterThanThreshold' '1' '60' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Count' && echo "Created alarm: ${name_and_description}"
    create_alarm_by_object "${ES_NAME}" 'ES' 'Minimum' 'FreeStorageSpace' 'LessThanThreshold' '2048' '60' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Megabytes' && echo "Created alarm: ${name_and_description}"
    create_alarm_by_object "${ES_NAME}" 'ES' 'Maximum' 'Nodes' 'LessThanThreshold' '5' '28800' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Count' && echo "Created alarm: ${name_and_description}"
    create_alarm_by_object "${ES_NAME}" 'ES' 'Average' 'JVMMemoryPressure' 'GreaterThanThreshold' '80' '120' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Percent' && echo "Created alarm: ${name_and_description}"
    create_alarm_by_object "${ES_NAME}" 'ES' 'Maximum' 'MasterJVMMemoryPressure' 'GreaterThanThreshold' '80' '120' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Percent' && echo "Created alarm: ${name_and_description}"
    create_alarm_by_object "${ES_NAME}" 'ES' 'Average' 'CPUUtilization' 'GreaterThanThreshold' '80' '120' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Percent' && echo "Created alarm: ${name_and_description}"
    create_alarm_by_object "${ES_NAME}" 'ES' 'Maximum' 'MasterCPUUtilization' 'GreaterThanThreshold' '50' '180' '2' '3' \
        "${ALARM_ACTION}" 'ignore' 'Percent' && echo "Created alarm: ${name_and_description}"
  done
}

configure_elb_alarms() {
  echo "ELB list:"
  aws --profile $AWS_PROFILE elb describe-load-balancers | jq -r '.LoadBalancerDescriptions[].LoadBalancerName' || exit $?
  LB_LIST=($(aws --profile $AWS_PROFILE elb describe-load-balancers | jq -r '.LoadBalancerDescriptions[].LoadBalancerName'))

  for LB_NAME in "${LB_LIST[@]}"; do
    clean_alarms_from_aws 'ELB' ${LB_NAME}
    # Load Balancer has healthy instances < 2
    create_alarm_by_object "${LB_NAME}" 'ELB' 'Minimum' 'HealthyHostCount' 'LessThanThreshold' '1' '60' '2' '3' \
        "${URGENT_ALARM_ACTION}" 'breaching' && echo "Created alarm: ${name_and_description}"
    # Load Balancer Low Latency Check
    create_alarm_by_object "${LB_NAME}" 'ELB' 'Average' 'Latency' 'GreaterThanThreshold' '0.3' '60' '2' '3' \
        "${ALARM_ACTION}" 'notBreaching' 'Seconds' && echo "Created alarm: ${name_and_description}"
    # Load Balancer High Latency Check
    create_alarm_by_object "${LB_NAME}" 'ELB' 'Average' 'Latency' 'GreaterThanThreshold' '0.3' '60' '4' '5' \
        "${URGENT_ALARM_ACTION}" 'notBreaching' 'Seconds' && echo "Created alarm: ${name_and_description}"
    # Load Balancer 5XX
    create_alarm_by_object "${LB_NAME}" 'ELB' 'Sum' 'HTTPCode_Backend_5XX' 'GreaterThanOrEqualToThreshold' '16' '60' '3' '5' \
        "${URGENT_ALARM_ACTION}" 'notBreaching' && echo "Created alarm: ${name_and_description}"
    # Load Balancer 4XX
    create_alarm_by_object "${LB_NAME}" 'ELB' 'Sum' 'HTTPCode_Backend_4XX' 'GreaterThanThreshold' '70' '60' '3' '5' \
        "${ALARM_ACTION}" 'notBreaching' && echo "Created alarm: ${name_and_description}"
    # Load Balancer Backend connection errors
    create_alarm_by_object "${LB_NAME}" 'ELB' 'Sum' 'BackendConnectionErrors' 'GreaterThanThreshold' '1' '60' '2' '3' \
        "${URGENT_ALARM_ACTION}" 'notBreaching' && echo "Created alarm: ${name_and_description}"
  done
}

configure_nat_gateways() {
  echo "NATGW list:"
  #   aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId' || exit $?
  if [[ $(aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId' | tail -n1) != 'null' ]]; then
      NATGW_LIST=($(aws ec2 describe-nat-gateways | jq -r '.NatGateways[].NatGatewayId'))
  else
      echo "Cannot find any NAT gateway resource"
      exit 12
  fi

  for NATGW_NAME in "${NATGW_LIST[@]}"; do
    clean_alarms_from_aws 'NATGateway' ${NATGW_NAME}
    create_alarm_by_object "${NATGW_NAME}" 'NATGateway' 'Maximum' 'IdleTimeoutCount' 'GreaterThanThreshold' '150' '60' '2' '3' "${ALARM_ACTION}" 'ignore' 'Count' 
  done
}

configure_opsworks_alarms() {
  echo "OpsWorks StacksIds: "
  aws --profile $AWS_PROFILE opsworks describe-stacks | jq -r '.Stacks[].StackId' || exit $?
  OPSWORKS_STACK_ID_LIST=($(aws --profile $AWS_PROFILE opsworks describe-stacks | jq -r '.Stacks[].StackId'))

  for OPSWORKS_STACK_ID in "${OPSWORKS_STACK_ID_LIST[@]}"; do
    OPSWORKS_NAME=$(aws --profile $AWS_PROFILE opsworks describe-stacks --stack-ids $OPSWORKS_STACK_ID | jq -r '.Stacks[].Name')
    clean_alarms_from_aws 'OpsWorks' ${OPSWORKS_NAME}
    # cpu_user > 60%
    create_alarm_by_object "${OPSWORKS_NAME}" 'OpsWorks' 'Average' 'cpu_user' 'GreaterThanThreshold' '60' '120' '2' '3' \
        "${URGENT_ALARM_ACTION}" && echo "Created alarm: ${name_and_description}"
    # load_5 > 1.2
    create_alarm_by_object "${OPSWORKS_NAME}" 'OpsWorks' 'Average' 'load_5' 'GreaterThanThreshold' '1.2' '160' '3' '4' \
        "${URGENT_ALARM_ACTION}" && echo "Created alarm: ${name_and_description}"
  done
}

# https://docs.aws.amazon.com/cli/latest/reference/rds/describe-db-instances.html
configure_rds_alarms() {
  echo "RDS Instances: "
  aws --profile $AWS_PROFILE rds describe-db-instances | jq -r '.DBInstances[].DBInstanceIdentifier' || exit $?
  RDS_INSTANCE_LIST=($(aws --profile $AWS_PROFILE rds describe-db-instances | jq -r '.DBInstances[].DBInstanceIdentifier'))

  for RDS_INSTANCE in "${RDS_INSTANCE_LIST[@]}"; do
    clean_alarms_from_aws 'RDS' ${RDS_INSTANCE}
    if [[ ${RDS_INSTANCE} =~ backup || ${RDS_INSTANCE} =~ cold || ${RDS_INSTANCE} =~ replica || ${RDS_INSTANCE} =~ restored ]]; then
        continue
    else
        # Database CPU > 80%
        create_alarm_by_object "${RDS_INSTANCE}" 'RDS' 'Average' 'CPUUtilization' 'GreaterThanThreshold' '80' '60' '2' '3' \
            "${URGENT_ALARM_ACTION}" '' 'Percent' && echo "Created alarm: ${name_and_description}"
        # Disk QD > 5
        create_alarm_by_object "${RDS_INSTANCE}" 'RDS' 'Average' 'DiskQueueDepth' 'GreaterThanThreshold' '5' '60' '2' '3' \
            "${URGENT_ALARM_ACTION}" '' 'Count' && echo "Created alarm: ${name_and_description}"
        # FreeableMemory < 520 MB
        create_alarm_by_object "${RDS_INSTANCE}" 'RDS' 'Average' 'FreeableMemory' 'LessThanThreshold' '520000000' '60' '2' '3' \
            "${ALARM_ACTION}" '' 'Bytes' && echo "Created alarm: ${name_and_description}"
        # FreeStorageSpace Space < 20 GB
        create_alarm_by_object "${RDS_INSTANCE}" 'RDS' 'Average' 'FreeStorageSpace' 'LessThanThreshold' '20000000000' '60' '2' '3' \
            "${ALARM_ACTION}" '' 'Bytes' && echo "Created alarm: ${name_and_description}"
    fi
    if [[ ${RDS_INSTANCE} =~ replica ]]; then
        # ReplicaLag > 2.0
        create_alarm_by_object "${RDS_INSTANCE}" 'RDS' 'Average' 'ReplicaLag' 'GreaterThanThreshold' '2' '60' '3' '4' \
            "${URGENT_ALARM_ACTION}" 'missing' '' && echo "Created alarm: ${name_and_description}"
    fi
  done
}

# https://docs.aws.amazon.com/cli/latest/reference/elasticache/describe-cache-clusters.html
configure_redis_alarms() {
  echo "Redis Instances: "
  aws --profile $AWS_PROFILE elasticache describe-cache-clusters | jq -r '.CacheClusters[].CacheClusterId' || exit $?
  REDIS_CLUSTER_LIST=($(aws --profile $AWS_PROFILE elasticache describe-cache-clusters | jq -r '.CacheClusters[].CacheClusterId'))

  for REDIS_CLUSTER in "${REDIS_CLUSTER_LIST[@]}"; do
    clean_alarms_from_aws 'ElastiCache' ${REDIS_CLUSTER}

    # Cluster CPU > 50%
    create_alarm_by_object "${REDIS_CLUSTER}" 'ElastiCache' 'Average' 'CPUUtilization' 'GreaterThanThreshold' '50' '60' '2' '3' \
        "${URGENT_ALARM_ACTION}" '' 'Percent' && echo "Created alarm: ${name_and_description}"

    # Cluster FreeableMemory < 100 MB
    create_alarm_by_object "${REDIS_CLUSTER}" 'ElastiCache' 'Average' 'FreeableMemory' 'LessThanThreshold' '100000000' '60' '2' '3' \
        "${URGENT_ALARM_ACTION}" '' 'Bytes' && echo "Created alarm: ${name_and_description}"

    # Cluster NewConnections > 100
    create_alarm_by_object "${REDIS_CLUSTER}" 'ElastiCache' 'Average' 'NewConnections' 'GreaterThanThreshold' '100' '60' '2' '3' \
        "${ALARM_ACTION}" '' 'Count' && echo "Created alarm: ${name_and_description}"
  done
}

# https://docs.aws.amazon.com/cli/latest/reference/sqs/list-queues.html
configure_sqs_alarms() {
  echo "SQS Queues: "
  aws --profile $AWS_PROFILE sqs list-queues | jq -r '.QueueUrls[]' || exit $?
  SQS_URL_LIST=($(aws --profile $AWS_PROFILE sqs list-queues | jq -r '.QueueUrls[]'))

  for SQS_URL in "${SQS_URL_LIST[@]}"; do
    SQS_NAME=${SQS_URL##*/}
    clean_alarms_from_aws 'SQS' ${SQS_NAME}
    # ApproximateAgeOfOldestMessage > 120s
    create_alarm_by_object "${SQS_NAME}" 'SQS' 'Maximum' 'ApproximateAgeOfOldestMessage' 'GreaterThanThreshold' '120' '60' '2' '3' \
        "${ALARM_ACTION}" '' 'Seconds' && echo "Created alarm: ${name_and_description}"
    # Custom alarm metric for Push-Events
    # ApproximateAgeOfOldestMessage > 120s in 1 datapoint
    create_alarm_by_object "${SQS_NAME}" 'SQS' 'Maximum' 'ApproximateAgeOfOldestMessage' 'GreaterThanThreshold' '120' '60' '2' '3' \
        "${URGENT_ALARM_ACTION}" '' 'Seconds' && echo "Created alarm: ${name_and_description}"
  done
}

create_all_alarms(){
    configure_elb_alarms
    configure_alb_alarms
    configure_ec2_alarms
    configure_rds_alarms
    configure_redis_alarms
    configure_sqs_alarms
    configure_opsworks_alarms
    configure_nat_gateways
    configure_elastisearch_alarms
}





