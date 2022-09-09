#!/usr/bin/env bash

# BACKUP_KEY=id_rsa.pem.pub
BACKUP_KEY=project-production-offsitedb.key.pub
INSTANCE_CLASS="db.m5.xlarge"
DB_PASSWORD=$(openssl rand -hex 16)
# SECURITY_GROUP="sg-1da1cb78"
SECURITY_GROUP="sg-a07174c5"
RDS_PARAM_GROUP="backup-mysql8"
BACKUP_RDS_INSTANCE="backup-${RDS_INSTANCE}"
SNAPSHOT_IDENTIFIER=$(aws rds describe-db-snapshots --db-instance-identifier ${RDS_INSTANCE} --snapshot-type automated | jq -r '.DBSnapshots[].DBSnapshotIdentifier' | tail -n1)
SQLDUMPERROR="/tmp/sqldumpfail.flag"
SNAPSHOT_STATUS=""
