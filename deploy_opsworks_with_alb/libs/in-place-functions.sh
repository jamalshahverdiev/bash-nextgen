#!/usr/bin/env bash

in_place_usage() {
    echo "Usage: "
    echo "$0 -s STACK_NAME -t DOCKER_IMAGE_TAG [ -i DOCKER_IMAGE_NAME ]"
    echo " -s STACK_NAME          OpsWorks Stack name"
    echo " -i DOCKER_IMAGE_NAME   Docker image name"
    echo " -t DOCKER_IMAGE_TAG    Docker image tag (version)"
    exit 64
}

get_arguments_with_parameters(){
    while getopts_long ':s:i:t: stackname: dockerimagename: dockerimagetag:' OPTKEY; do
        case ${OPTKEY} in
            's'|'stackname')        STACK_NAME="$OPTARG" ;;
            'i'|'dockerimagename')  DOCKER_IMAGE_NAME="$OPTARG" ;;
            't'|'dockerimagetag')   DOCKER_IMAGE_TAG="$OPTARG" ;;
            '?')            echo "INVALID OPTION -- ${OPTARG}"; in_place_usage >&2 ; exit 1 ;;
            ':')            echo "MISSING ARGUMENT for option -- ${OPTARG}"; in_place_usage >&2 ; exit 1 ;;
            *)              echo "Misconfigured OPTSPEC or uncaught option -- ${OPTKEY}"; in_place_usage >&2 ; exit 1 ;;
        esac
    done
}

deploy_to_all_instances_without_elb(){
    echo "No Load balancer found for $STACK_NAME"
    echo "Will deploy to all instances"
    OPS_INSTANCE_IDS=$(aws opsworks describe-instances --stack-id $STACK_ID| jq -r '.Instances[].InstanceId')
    for OPS_INSTANCE_ID in "${OPS_INSTANCE_IDS[@]}"; do
        INSTANCE_HOSTNAME=$(aws opsworks describe-instances --stack-id $STACK_ID | jq -r --arg OPS_INSTANCE_ID "$OPS_INSTANCE_ID" '.Instances[]|select(.InstanceId==$OPS_INSTANCE_ID)|.Hostname')
        echo "Deploing to instance $INSTANCE_HOSTNAME"
        DEPLOYMENT_ID=$(aws opsworks create-deployment --stack-id $STACK_ID --app-id $APP_ID --instance-ids $OPS_INSTANCE_ID --command Name="deploy" | jq -r .DeploymentId)
        # wait for deployment to finish
        while [ $(aws opsworks describe-deployments --deployment-ids $DEPLOYMENT_ID | jq -r '.Deployments[].Status') == "running" ]; do
            echo "Waiting for deployment $DEPLOYMENT_ID to finish on instance $INSTANCE_HOSTNAME"
            sleep 6
        done
        
        if [ $(aws opsworks describe-deployments --deployment-ids $DEPLOYMENT_ID | jq -r '.Deployments[].Status') != "successful" ]; then
            echo "ERROR: deployment $DEPLOYMENT_ID  failed. Stopping"
            exit 64
        fi
    done
}

add_and_wait_instance_to_become_inservice_in_elb(){
    # add instance back to ELB
    aws elb register-instances-with-load-balancer --load-balancer-name $ELBNAME --instances $EC2INSTANCE --region "$AWS_DEFAULT_REGION"
    # wait for instance to become "InService"
    counter=0
    while [ $(aws elb describe-instance-health --load-balancer-name $ELBNAME --region "$AWS_DEFAULT_REGION" \
          | jq -r --arg EC2INSTANCE "$EC2INSTANCE" '.InstanceStates[]| select(.InstanceId==$EC2INSTANCE)|.State') != "InService" ]; do
        let "counter += 10"
        if [ "$counter" -ge 300 ]; then
            echo "ERROR: Instance $INSTANCE_HOSTNAME is not healthy after $counter seconds"; exit 64
        fi
        sleep 10; echo "Waited $counter seconds for instance $INSTANCE_HOSTNAME to become healthy"
    done
}

add_and_wait_instance_to_become_healthy_in_tg_alb(){
    INPUT_INSTANCE_ID=$1
    # add instance back to ALB Target Group
    aws elbv2 register-targets --target-group-arn ${ALB_TG_ARN} --targets Id=${INPUT_INSTANCE_ID}
    # wait for instance to become "healthy"
    counter=0
    while [ $(aws elbv2 describe-target-health --target-group-arn ${ALB_TG_ARN} --region "${AWS_DEFAULT_REGION}" --targets Id=${INPUT_INSTANCE_ID} \
        | jq -r '.TargetHealthDescriptions[].TargetHealth.State') != "healthy" ]; do
        let "counter += 10"
        if [ "$counter" -ge 300 ]; then 
            echo "ERROR: Instance $INSTANCE_HOSTNAME is not healthy after $counter seconds"; exit 64 
        fi
        sleep 10; echo "Waited $counter seconds for instance $INSTANCE_HOSTNAME to become healthy"
    done
}

get_print_instance_hostname_and_id(){
    LB_NAME=$1
    INSTANCE_HOSTNAME=$(aws opsworks describe-instances --stack-id $STACK_ID | jq -r --arg EC2INSTANCE "$EC2INSTANCE" '.Instances[] | select(.Ec2InstanceId==$EC2INSTANCE) | .Hostname')
    OPS_INSTANCE_ID=$(aws opsworks describe-instances --stack-id $STACK_ID | jq -r --arg EC2INSTANCE "$EC2INSTANCE" '.Instances[] | select(.Ec2InstanceId==$EC2INSTANCE) | .InstanceId')
    echo "Deploying EC2INSTANCE=$INSTANCE_HOSTNAME"
    echo "Removing instance $INSTANCE_HOSTNAME from load balancer ${LB_NAME}"
}

deregister_instance_from_elb(){
    get_print_instance_hostname_and_id ${ELBNAME}
    aws elb deregister-instances-from-load-balancer --load-balancer-name $ELBNAME --instances $EC2INSTANCE --region "$AWS_DEFAULT_REGION"
    sleep 20
}

deregister_instance_from_tg_alb(){
    INPUT_TG_ARN=$1
    INPUT_INSTANCE_ID=$2
    get_print_instance_hostname_and_id ${ALB_NAME}
    aws elbv2 deregister-targets --target-group-arn ${INPUT_TG_ARN} --targets Id=${INPUT_INSTANCE_ID} 
    # aws elbv2 wait target-deregistered --target-group-arn ${INPUT_TG_ARN} --targets Id=${INPUT_INSTANCE_ID}
    sleep 20
}

run_and_wait_opsworks_deployment(){
    # run opswoks deploy command
    DEPLOYMENT_ID=$(aws opsworks create-deployment --stack-id $STACK_ID --app-id $APP_ID --instance-ids $OPS_INSTANCE_ID --command Name="deploy" | jq -r .DeploymentId)
    # wait for deployment to finish
    while [ $(aws opsworks describe-deployments --deployment-ids $DEPLOYMENT_ID | jq -r '.Deployments[].Status') == "running" ]; do
        echo "Waiting for deployment $DEPLOYMENT_ID to finish on instance $INSTANCE_HOSTNAME"; sleep 10
    done

    if [ $(aws opsworks describe-deployments --deployment-ids $DEPLOYMENT_ID | jq -r '.Deployments[].Status') != "successful" ]; then
        echo "ERROR: deployment $DEPLOYMENT_ID  failed. Stopping"; exit 64
    fi
}

deploy_to_all_instances_with_elb(){
    echo "Load balancer $ELBNAME found for $STACK_NAME"
    echo "Will deploy to all instances on ELB $ELBNAME"
    ELBINSTANCES=($(aws elb describe-instance-health --load-balancer-name $ELBNAME --region "$AWS_DEFAULT_REGION" | jq -r '.InstanceStates[] |.InstanceId'))
    echo "All ELB Instances: ${ELBINSTANCES[@]}"
    for EC2INSTANCE in "${ELBINSTANCES[@]}"; do
        deregister_instance_from_elb
        run_and_wait_opsworks_deployment
        add_and_wait_instance_to_become_inservice_in_elb
        echo "Deployment of ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} to $INSTANCE_HOSTNAME finished."
    done
}

deploy_to_all_instances_with_alb(){
    get_alb_name_and_tg_arn
    get_all_healty_instances_tg_in_alb
    count=1
    for EC2INSTANCE in "${ONLINE_ALB_TG_INSTANCES[@]}"; do
        echo "This is online EC2 instance: ${EC2INSTANCE}"
        # sleep 100 seconds, before removing old instances from ALB (This value took from ALB TG Properties "Slow start duration")
        if [ ${count} != 1 ]; then sleep 100; fi
        deregister_instance_from_tg_alb "${ALB_TG_ARN}" "${EC2INSTANCE}"
        run_and_wait_opsworks_deployment
        add_and_wait_instance_to_become_healthy_in_tg_alb "${EC2INSTANCE}"
        echo "Deployment of ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_TAG} to $INSTANCE_HOSTNAME finished."
        ((count+=1))
    done
}