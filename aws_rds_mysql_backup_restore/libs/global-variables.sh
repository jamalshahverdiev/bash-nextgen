#!/usr/bin/env bash

db_check_result_file_name='db_check_result.txt'
restore_db_check_result_file_name='restore_db_check_result_file_name.txt'
declare -A schema_names srch_table_cnt_in_schms
srch_table_cnt_in_schms=([main]='USER VIRTUAL_PHONE_NUMBER LAWFUL_INTERCEPTION_NUMBERS' [softswitch]='TSAN' [messages]='MESSAGE')
# srch_table_cnt_in_schms=([project-staging]='USER VIRTUAL_PHONE_NUMBER LAWFUL_INTERCEPTION_NUMBERS' [project-smpp-staging]='SMPP_INCOMING SMPP_OUTGOING' [project-soft-switch-staging]='TSAN' [project-messages-staging]='MESSAGE')