# Usage.
### Prerequisites:

You have the following tools installed on your computer:

- [Git](https://git-scm.com/downloads "Git downloads page") 
- [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html "AWS CLI install page")
- [JQ](https://stedolan.github.io/jq/download/ "Tool to parse Json data")

## In order to have a working environment please follow the sequence shown below:
- [x] Prepare environment
- [x] Create Shodan Objects
- [x] Delete created objects 

## Prepare environment
- Create IAM Policy and user which will use this policy
- Clone repository and login to AWS

#### Create IAM Policy and user which will use this policy
```bash
$ policy_name='test-jenkins-policy'; policy_file_name='jenkins-describer-policy.json'; aws_iam_user_name='test-jenkins-shodan'
$ policy_arn=$(aws iam create-policy --policy-name ${policy_name} --policy-document file://${policy_file_name} | jq -r '.Policy.Arn')
$ aws iam create-user --user-name ${aws_iam_user_name}
$ aws iam attach-user-policy --user-name ${aws_iam_user_name} --policy-arn ${policy_arn}
$ aws_iam_user_object=$(aws iam create-access-key --user-name ${aws_iam_user_name})
$ access_key_id=$(echo ${aws_iam_user_object} | jq -r '.AccessKey.AccessKeyId')
$ secret_access_key=$(echo ${aws_iam_user_object} | jq -r '.AccessKey.SecretAccessKey')
```

#### Clone repository and login to AWS
Use outputs from `access_key_id` and `secret_access_key` variables to get values of `aws configure` command.
```bash
$ aws configure
```

## Create Shodan Objects
Execute `start.sh` with one of the environments (`prod` or `staging`) to prepate objects in Shodan:
```bash
$ ./start.sh --env staging
```
### Code details

- `libs` folder contains functions and variable files which used inside `aws_rdsdb_names.sh`, `eip_ec2_names.sh`, `internet_facing_elbs.sh` and `delete_shodan_alerts.sh` scripts.
- `start.sh` main file which needs `--env` parameter with argument to create objects. It will calls `aws_rdsdb_names.sh`, `eip_ec2_names.sh` and `internet_facing_elbs.sh`  scripts with argument from `--env` parameter. 
- `internet_facing_elbs.sh` script creates shodan objects for `ElasticLoadBalancer` public IP addresses 
- `eip_ec2_names.sh` script creates shodan objects for `ElasticIPs` public IP addresses.
- `aws_rdsdb_names.sh` script creates shodan objects for `RDS MySQL` database public IP addresses.
  
## Delete created objects
If you want to delete created objects in Shodan just execute `delete_shodan_alerts.sh` script with environment argument. Don't forget change `shodan_api_key` variable value to the right one inside `libs/small_variables.sh` file.
```bash
$ ./delete_shodan_alerts.sh staging
```