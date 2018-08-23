AWS_SCRIPTS_DIR="${HOME}/PATH-TO-WHERE-YOU-DOWNLOADED/aws-token-refresh"

AWS_CONF_DIR="${HOME}/.aws"

clear_aws_env ()
{
    unset AWS_SECURITY_TOKEN_EXPIRATION
    unset AWS_SESSION_TOKEN
    unset ADMIN_AWS_SECURITY_TOKEN
    unset AWS_MFA_SN
    unset ADMIN_AWS_MFA_SN
    unset ADMIN_AWS_KEY
    unset ADMIN_AWS_SECRET
    unset ADMIN_AWS_KEY_ROOT
    unset ADMIN_AWS_SECRET_ROOT
    unset ADMIN_AWS_ACCT
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SECURITY_TOKEN
}

token ()
{
    ${AWS_SCRIPTS_DIR}/aws-token-or-role-refresh.sh token "$@"
}


awsenv ()
{
    if [ "$#" -eq 0 ]; then
        list_aws_profiles
        return
    fi

    ENVNAME="${1}"
    if [ ! -f ${AWS_CONF_DIR}/aws-profiles/${ENVNAME} ]; then
       echo "No such environment"
       return 1
    fi

    clear_aws_env
    ${AWS_SCRIPTS_DIR}/aws-token-or-role-refresh.sh awsenv ${ENVNAME}
    source ${AWS_CONF_DIR}/current-env.txt
    echo "AWS environment variables populated for '${ENVNAME}'"
}

list_aws_profiles()
{
    find -L ${AWS_CONF_DIR}/aws-profiles -type f ! -name '.*' | sed 's#'"${AWS_CONF_DIR}/aws-profiles"'/\(.*\)#\1#'
}
