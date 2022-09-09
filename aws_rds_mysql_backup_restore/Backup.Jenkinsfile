pipeline {
    agent { label 'backup-controller-production' }
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
                          userRemoteConfigs                : [[credentialsId: '9487578sd-23nd-43hn-344k-123js934ksk', url: 'git@bitbucket.org:projecttelecom/project-tools.git']]])
            }
        }
        stage('Execute backup script') {
            steps {
                withAWS(credentials: 'RDS_backup_user', region: 'eu-west-1') {
                    sh '''
                    pushd db-backup-v2
                    bash -xe backup.sh -i production-hot-db -u 'rds-production@offline-backups.projectapp.net:/storage/rds-production/ 22' -u 'rds-production@city.projectapp.net:/storage/rds-production/ 24422'
                    popd
                    '''
                }
                slackSend channel: "#devops", color: 'good', message: ":sailboat: <${env.BUILD_URL}|Jenkins job> successfully archived TAR for the production."
            }
        }
    }
    post { failure { slackSend channel: "#devops", color: 'danger', message: ":skull: Backup process of the MySQL database was unsuccessful." } }
}
