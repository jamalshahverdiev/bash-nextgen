pipeline {
    agent { label 'backup-controller-production' }
    parameters {
        string(name: 'TAR_FILE_NAME', defaultValue: '')
        string(name: 'SECURITY_GROUP_ID', defaultValue: 'sg-a07174c5')
        string(name: 'ALLOCATED_STORAGE_GB', defaultValue: '1700')
        string(name: 'BACKUP_DESTINATION', defaultValue: 'rds-production@offline-backups.projectapp.net:/storage/rds-production/')
    }
    environment {
        RESTORE_PRIVATE_KEY = credentials('AWS_RDS_BACKUP_RESTORE_PRODUCTION_PRIVATE_KEY')
        // RESTORE_PRIVATE_KEY = credentials('AWS_RDS_BACKUP_RESTORE_STAGING_TEST_PRIVATE_KEY')
    }
    options {
        timestamps ()
        buildDiscarder(logRotator(numToKeepStr: "100"))
    }
    stages {
        stage('Check new script from repository') {
            steps {
                checkout([$class                           : 'GitSCM', branches: [[name: '*/master']],
                          doGenerateSubmoduleConfigurations: false,
                          extensions                       : [[$class: 'SparseCheckoutPaths', sparseCheckoutPaths: [[path: 'db-backup-v2']]]], submoduleCfg: [],
                          userRemoteConfigs                : [[credentialsId: '35500a42-19cc-4b5a-851e-4754bbe2e2fb', url: 'git@bitbucket.org:projecttelecom/project-tools.git']]])
            }
        }
        stage('Execute backup script') {
            steps {
                withAWS(credentials: 'RDS_backup_user', region: 'eu-west-1') {
                // withAWS(credentials: 'AWS_RDS_STAGING_TEST_KEY', region: 'eu-west-1') {
                    sh """#!/bin/bash
                    pushd db-backup-v2
                    if [ -z \${TAR_FILE_NAME} ]; then 
                        TAR_FILE_NAME=\$(ssh rds-production@offline-backups.projectapp.net "ls /storage/rds-production/production-hot-db-*.tar | tail -n1 | cut -f4 -d '/'")
                    fi
                    ./restore.sh -k ${env.RESTORE_PRIVATE_KEY} -b \${TAR_FILE_NAME} -g \${SECURITY_GROUP_ID} -d \${ALLOCATED_STORAGE_GB} -l \${BACKUP_DESTINATION} 
                    popd
                    """
                }
                slackSend channel: "#devops", color: 'good', message: ":sailboat: <${env.BUILD_URL}|Jenkins job> restored MySQL TAR archive to the production."
            }
        }
    }
    post { failure { slackSend channel: "#devops", color: 'danger', message: ":skull: The restore process of the MySQL database was unsuccessful." } }
}