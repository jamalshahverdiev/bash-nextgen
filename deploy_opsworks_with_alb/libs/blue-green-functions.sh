#!/usr/bin/env bash

blue_green_usage() {
    echo "Usage: "
    echo "blue-green-deploy.sh -s STACK_NAME -t DOCKER_IMAGE_TAG -i DOCKER_IMAGE_NAME "
    echo " -s STACK_NAME          OpsWorks Stack name"
    echo " -i DOCKER_IMAGE_NAME   Docker image name"
    echo " -t DOCKER_IMAGE_TAG    Docker image tag (version)"
    echo " -a INSTANCE_TYPE       Default: $INSTANCE_TYPE"
    echo " -c INSTANCE_COUNT      Default: $INSTANCE_COUNT"
    echo " -n subnet-1 -n subnet-2 -n subnet-3  Note: multiple subnets supported with multiple flags "
    echo " -w WAIT_TIME           Default: $WAIT_TIME"
    exit 64
}

get_arguments_with_parameters(){
    while getopts_long ':s:i:t:a:c:n:w: stackname: dockerimagename: dockerimagetag: instancetype: instancecount: subnetids: waittime:' OPTKEY; do
        case ${OPTKEY} in
            's'|'stackname')            STACK_NAME="${OPTARG}" ;;
            'i'|'dockerimagename')      DOCKER_IMAGE_NAME="${OPTARG}" ;;
            't'|'dockerimagetag')       DOCKER_IMAGE_TAG="${OPTARG}" ;;
            'a'|'instancetype')         INSTANCE_TYPE="${OPTARG}" ;;
            'c'|'instancecount')        INSTANCE_COUNT="${OPTARG}" ;;
            'n'|'subnetids')            SUBNET_IDS+=("$OPTARG") ;;
            'w'|'waittime')             WAIT_TIME="${OPTARG}" ;;
            '?')            echo "INVALID OPTION -- ${OPTARG}"; blue_green_usage >&2 ; exit 1 ;;
            ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; blue_green_usage >&2 ; exit 1 ;;
            *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; blue_green_usage >&2 ; exit 1 ;;
        esac
    done
}

get_subnet_ids(){
    # SUBNET_IDS=($(aws opsworks describe-instances --stack-id $STACK_ID | jq -r '.Instances[].SubnetId'|sort|uniq))
    if [ ${#SUBNET_IDS[@]} -eq 0 ]; then
        echo "ERROR: SUBNET_IDS not specified"
        exit 65
    fi
    echo "SUBNET_IDS=${SUBNET_IDS[*]}"
}

check_if_opsworks_stack_have_eips(){
    # Check if Opsworks Stack has EIPs
    ELASTIC_IP_LIST=($(aws opsworks describe-elastic-ips --stack-id ${STACK_ID} | jq -r ".ElasticIps[].InstanceId"))
    if [ ${#ELASTIC_IP_LIST[@]} -ne 0 ]
    then
        echo "ERROR: Elastic IP found: ELASTIC_IP_LIST=${ELASTIC_IP_LIST[*]}, use in-place-deploy.sh with suport for EIP"
        exit 68
    fi
}

remove_stopped_instances(){
    # Remove stopped instances
    STOPPED_INSTANCES=($(aws opsworks describe-instances --stack-id $STACK_ID | jq -r '.Instances[] | select(.Status!="online") | .InstanceId'))
    if [ ${#STOPPED_INSTANCES[@]} -ne 0 ]; then
        for STOPPED_INSTANCE in "${STOPPED_INSTANCES[@]}"; do aws opsworks delete-instance --instance-id $STOPPED_INSTANCE; done
    fi
}

get_blue_and_stack_instances(){
    BLUE_EC2_INSTANCES=($(aws opsworks describe-instances --stack-id $STACK_ID | jq -r '.Instances[].Ec2InstanceId'))
    BLUE_STACK_INSTANCES=($(aws opsworks describe-instances --stack-id $STACK_ID | jq -r '.Instances[].InstanceId'))
    echo "BLUE_EC2_INSTANCES=${BLUE_EC2_INSTANCES[*]}"
    echo "BLUE_STACK_INSTANCES=${BLUE_STACK_INSTANCES[*]}"
}

verify_all_running_instances_in_elb() {
    # Maybe we should verify all running instances online in ELB?
    ONLINE_ELB_INSTANCES=($(aws elb describe-instance-health --load-balancer-name $ELB_NAME --region "eu-west-1" | jq -r '.InstanceStates[] | select(.State=="InService") | .InstanceId'))
    echo "ONLINE_ELB_INSTANCES=${ONLINE_ELB_INSTANCES[*]}"
}

deploy_green_instances() {
    # Deploy green instances
    aws opsworks update-app --app-id $APP_ID --environment Key=IMAGE_NAME,Value=$DOCKER_IMAGE_NAME Key=IMAGE_TAG,Value=$DOCKER_IMAGE_TAG "${APP_ENVIRONMENT_VARS[@]}"

    for INSTANCE_NUMBER in $(seq 1 $INSTANCE_COUNT); do
        # Choose subnet for instance like ($INSTANCE_NUMBER % ${#SUBNET_IDS[@]})
        INSTANCE_SUBNET_ID=${SUBNET_IDS[(($INSTANCE_NUMBER % ${#SUBNET_IDS[@]}))]}
        AVAILABILITY_ZONE=$(aws ec2 describe-subnets --subnet-ids $INSTANCE_SUBNET_ID | jq -r  '.Subnets[].AvailabilityZone')
        NONSENSE=$(date +%N)
        GREENINSTANCE_HOSTNAME=${STACK_NAME}-${DOCKER_IMAGE_TAG//./-}${AVAILABILITY_ZONE: -1}${NONSENSE:0:2}
        GREENINSTANCE_ID=$(aws opsworks create-instance --stack-id $STACK_ID --layer-ids $LAYER_ID --instance-type $INSTANCE_TYPE --hostname ${GREENINSTANCE_HOSTNAME} \
            --root-device-type ebs --block-device-mappings "DeviceName=ROOT_DEVICE,Ebs={VolumeSize=25,VolumeType=gp2}" --subnet-id $INSTANCE_SUBNET_ID \
            | jq -r '.InstanceId')
        GREENINSTANCE_IDS+=("$GREENINSTANCE_ID")
        aws opsworks start-instance --instance-id "$GREENINSTANCE_ID"
    done
}

wait_opsworks_instance_until_online(){
    aws opsworks wait instance-online --instance-ids "${GREENINSTANCE_IDS[@]}"
    GREENINSTANCE_EC2IDS=($(aws opsworks describe-instances --instance-ids "${GREENINSTANCE_IDS[@]}" | jq -r '.Instances[].Ec2InstanceId'))
}

wait_green_instances_online_in_elb() {
    # wait green instances online in ELB
    wait_opsworks_instance_until_online
    aws elb wait instance-in-service --load-balancer-name $ELB_NAME --instances "${GREENINSTANCE_EC2IDS[@]}"
}

wait_green_instances_online_tg_in_alb() {
    # wait green instances online in ALB
    wait_opsworks_instance_until_online
    for instance_id in "${GREENINSTANCE_EC2IDS[@]}"; do
        instance_state=$(aws ec2 describe-instances --instance-ids ${instance_id} | jq -r '.Reservations[].Instances[].State.Name')
        if [[ ${instance_state} -eq 'running' ]]; then aws elbv2 register-targets --target-group-arn ${ALB_TG_ARN} --targets Id=${instance_id}; fi
        aws elbv2 wait target-in-service --target-group-arn ${ALB_TG_ARN} --targets Id=${instance_id}
        # aws elbv2 wait target-in-service --target-group-arn ${ALB_TG_ARN} --targets Id=${instance_id} &
    done
    # wait
}

remove_blue_instances_from_elb() {
    # sleep 60 seconds, before removing old instances from ELB
    sleep 60
    # Remove blue instances from ELB
    aws elb deregister-instances-from-load-balancer --load-balancer-name $ELB_NAME --instances "${BLUE_EC2_INSTANCES[@]}"
    echo "Now you have $WAIT_TIME to cancel stopping blue instances" && sleep $WAIT_TIME
}

remove_blue_instances_from_alb(){
    # sleep 100 seconds, before removing old instances from ALB (This value took from ALB TG Properties "Slow start duration")
    sleep 100  
    # Remove blue instances from ALB Target Group
    for instance_id in "${BLUE_EC2_INSTANCES[@]}"; do
        aws elbv2 deregister-targets --target-group-arn ${ALB_TG_ARN} --targets Id=${instance_id} 
    done

    for instance_id in "${BLUE_EC2_INSTANCES[@]}"; do
        aws elbv2 wait target-deregistered --target-group-arn ${ALB_TG_ARN} --targets Id=${instance_id}
    done
    # wait
    echo "Now you have $WAIT_TIME to cancel stopping blue instances" && sleep $WAIT_TIME
}

stop_blue_instances() {
    for BLUE_INSTANCE_ID in "${BLUE_STACK_INSTANCES[@]}"; do aws opsworks stop-instance --instance-id $BLUE_INSTANCE_ID; done
}


deploy_to_all_instances_with_alb() {
    get_alb_name_and_tg_arn
    get_all_healty_instances_tg_in_alb
    deploy_green_instances
    wait_green_instances_online_tg_in_alb
    remove_blue_instances_from_alb
    stop_blue_instances    
}

deploy_to_all_instances_with_elb() {
    echo "Load balancer $ELB_NAME found for $STACK_NAME"
    verify_all_running_instances_in_elb
    deploy_green_instances
    wait_green_instances_online_in_elb
    remove_blue_instances_from_elb
    stop_blue_instances
}