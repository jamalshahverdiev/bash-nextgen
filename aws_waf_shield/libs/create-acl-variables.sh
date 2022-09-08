#!/usr/bin/env bash
visibility_config='SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=WebAclRuleGroupForWebACL'
declare -A ip_sets=(
    [DEFAULT_VPC]="172.31.0.0/16" \
    [EIP]="34.243.38.200/32 52.16.12.64/32 54.77.207.9/32 54.72.171.21/32 52.209.33.101/32 99.80.246.163/32 34.248.220.239/32 52.30.10.169/32 18.202.3.216/32 52.208.245.2/32" \
    [NOT_FROM_IPS]="80.235.78.122/32" \
    [PARTNERS]="62.34.202.126/32 151.80.169.192/27 40.112.64.0/19 212.47.254.59/32 195.36.155.64/32 137.116.234.158/32 171.33.114.168/32 171.33.122.249/32" \
    [SITE24_SERVERS]="107.191.46.12/32 151.106.11.87/32 104.236.16.22/32 185.175.59.2/32 66.165.251.146/32 199.201.89.55/32 45.63.84.131/32 31.193.181.14/32 45.32.144.240/32 104.156.247.194/32" \
    [SMPP_VPC]="172.32.0.0/24" \
    [VOIP_SERVERS]="151.80.169.192/27 89.34.16.160/27 149.202.214.141/32 94.130.195.142/32 195.201.78.144/28"
)

declare -A regex_pattern_sets=(
    [AccountTakeOverEndPoints]='[{"RegexString": "/mobile/onboarding/login"},{"RegexString": "/mobile/v2/check-email"},{"RegexString": "/mobile/onboarding/register"}]'
    [ExcludeEndPoints]='[{"RegexString": "/healthOK"},{"RegexString": "/external/promotion/uber"},{"RegexString": "/external/web-site/bytel"},{"RegexString": "/external/branch/on-signup"},{"RegexString": "/external/sfr/get-status"},{"RegexString": "/web-site/email-unsubscribe"}]'
    [InternalURLEndpoints]='[{"RegexString": "^/voip/"},{"RegexString": "^/telco/"},{"RegexString": "^/freeswitch/"},{"RegexString": "^/internal/"},{"RegexString": "^/internal-admin/"},{"RegexString": "^/smpp/"},{"RegexString": "^/mms/"},{"RegexString": "^/relay/"},{"RegexString": "^/hystrix.stream"},{"RegexString": "^/async/"}]'
    [InternalURLEndpoints1]='[{"RegexString": "^/bapi/"},{"RegexString": "^/actuator/"}]'
    [MatchToRegex]='[{"RegexString": ".+"},{"RegexString": "[A-Z]*123$"},{"RegexString": ".{3,}"}]'
    [ProjectShortBadUserAgents]='[{"RegexString": "^project-(android|ios)\\/(\\.|\\d)+$"}]'
    [ProjectUserAgents]='[{"RegexString": "^project-msteams"},{"RegexString": "^b2b-web"},{"RegexString": "^project-ios"},{"RegexString": "^greetings-android"},{"RegexString": "^greetings-ios"},{"RegexString": "^b2b-android"},{"RegexString": "^b2b-ios"},{"RegexString": "^Site24x7"},{"RegexString": "^project-web"},{"RegexString": "^project-android"}]'
    [ProductionServerBlockInternalEndpointsRegex]='[{"RegexString": "^/voip/"},{"RegexString": "^/telco/"},{"RegexString": "^/freeswitch/"},{"RegexString": "^/internal/"},{"RegexString": "^/internal-admin/"},{"RegexString": "^/smpp/"},{"RegexString": "^/mms/"},{"RegexString": "^/relay/"},{"RegexString": "^/async/"},{"RegexString": "^/bapi/"}]'
    [ProductionServerBlockUnknownBotEmailCheck]='[{"RegexString": "/mobile/v2/check-email"},{"RegexString": "/mobile/onboarding/login"}]'
    [XUserAgentHeaders]='[{"RegexString": "^project-web"},{"RegexString": "^b2b-web"},{"RegexString": "^project-msteams"}]'
)

declare -A rule_groups_with_values=(
    [ProjectProductionAllow]='json_for_prod_allow'
    [ProjectProductionBlock]='json_for_prod_block'
    [ProjectAccountTakeOver]='json_for_prod_takeover'
)