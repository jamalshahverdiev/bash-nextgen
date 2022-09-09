#!/usr/bin/env bash

tar_file_path='/storage/rds-production'
file_names=$(ls -t /storage/rds-production/ | head -n2)
ssh_server='city.projectapp.net'
ssh_user='rds-production'

for file in ${file_names}; do scp -P 24422 ${tar_file_path}/${file} ${ssh_user}@${ssh_server}:${tar_file_path}/; done
if [ $? -eq 0 ]; then echo "TAR and MD5 file copied Successful to the Server."; fi