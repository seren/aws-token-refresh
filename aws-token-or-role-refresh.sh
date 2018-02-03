#!/usr/bin/env bash

# Wrapper for aws cli to handle MFA session tokens

set -euo pipefail


#################
# User vars

# The name of the profile is allowed to assume roles. Can be overriden by the "master_profile" value in the profile files.
DEFAULT_MASTER_PROFILE=

TOKEN_PREEXPIRATION_HOURS=2 # Hours before a token expires to try to get a fresh one instead of reusing it (tokens expire after 12 hours by default)
                            # Note: This doesn't apply to role tokens which expire after one hour max.

# How much feedback to display:
# LOG_LEVEL=ERROR
# LOG_LEVEL=WARN
LOG_LEVEL=INFO
# LOG_LEVEL=DEBUG

# Paths
AWS_CLI="$(which aws)"
AWS_DIR="${HOME}/.aws"
CREDENTIALS_FILE="${AWS_DIR}/credentials"
BOTO_CONFIG_FILE="${AWS_DIR}/config"
CREDENTIALS_SOURCE_DIR="${AWS_DIR}/aws-profiles"

# If you have a local MFA token generator that accepts profile names, you can specify it here
MFA_PROGRAM=""

##################





CWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

##########
# set up logging and debugging output
XTRACE="${XTRACE:-0}"

if [ "$XTRACE" == "1" ] || [ "$XTRACE" == "true" ] ; then
  set -x
  PS4="$(tput setaf 2)COMMAND: $(tput sgr0)"
fi

## Bash < 4 doesn't have associative arrays, so we can't use this
# declare -A log_levels
# log_levels=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)
function log_levels ()
{
  case $1 in
    DEBUG)  return 0 ;;
    INFO)   return 1 ;;
    WARN)   return 2 ;;
    ERROR)  return 3 ;;
    *)      echo "Invalid log level: $1" && exit 1;;
  esac
}

function loggable_timestamp {
  date "+%F %T"
}

function check_log_level {
  local global_log_level_name=${LOG_LEVEL:-INFO}
  # local global_log_level=${log_levels[$global_log_level_name]}
  # local event_log_level=${log_levels[$1]}
  log_levels $global_log_level_name
  local global_log_level=$?
  log_levels $1
  local event_log_level=$?
  [ $global_log_level -le $event_log_level ] && return 0 || return 1
}

function print_log_msg {
  if [ "$#" -lt 3 ]; then echo "$@" ; exit ; fi
  local level="$1"
  local color_code="$2"
  local message="${*:3}"

  check_log_level "$level"|| return 0

  tput setaf "$color_code"
  printf "%s %-7s: " "$(loggable_timestamp)" "$level"
  tput sgr0
  echo "$message"
}

function log_debug {
  if [ "$XTRACE" == "1" ]; then { set +x; } 2>/dev/null ; fi
  print_log_msg DEBUG 4 "$@"
  if [ "$XTRACE" == "1" ]; then { set -x; } 2>/dev/null ; fi
}

function log_info {
  if [ "$XTRACE" == "1" ]; then { set +x; } 2>/dev/null ; fi
  print_log_msg INFO 4 "$@"
  if [ "$XTRACE" == "1" ]; then { set -x; } 2>/dev/null ; fi
}

function log_warning {
  if [ "$XTRACE" == "1" ]; then { set +x; } 2>/dev/null ; fi
  print_log_msg WARNING 3 "$@"
  if [ "$XTRACE" == "1" ]; then { set -x; } 2>/dev/null ; fi
}

function log_error {
  if [ "$XTRACE" == "1" ]; then { set +x; } 2>/dev/null ; fi
  print_log_msg ERROR 1 "$@"
  if [ "$XTRACE" == "1" ]; then { set -x; } 2>/dev/null ; fi
}

##########


######################################
# Script functions
######################################
# Lists all the available profiles (eg. profile source files)
func_list_profiles () {
  echo "Avaliable profiles are:"
  echo "$(ls ${CREDENTIALS_SOURCE_DIR})"
  return 0
}

# Pulls a key value from a profile section
func_get_value_from_profile_source () {
  key_name=${1}
  sourcefile=${2}
  RETVAL=$(sed -n 's/'"${key_name}"' = \(.*\)/\1/p' ${sourcefile})
  return $?
}

# The whole song and dance to get an updated token using a profile and then insert it into that profile
func_update_token () {
  local PROFILE_NAME=$1
  # Remove the existing profile to remove old session tokens
  func_remove_profile_from_credentials_file "${PROFILE_NAME}"
  # Add the regular profile so we can request session tokens
  func_append_profile_to_credentials_file "${PROFILE_NAME}"
  func_update_boto_config
  # Now we can request a new token
  func_get_new_token "${PROFILE_NAME}"
  # Update the regular profile with the session token version
  func_remove_profile_from_credentials_file "${PROFILE_NAME}"
  func_append_sts_profile_to_credentials_file "${PROFILE_NAME}"
  # Remove consecutive blank lines
  sed -i.bak '/./,/^$/!d' ${CREDENTIALS_FILE}
  rm ${CREDENTIALS_FILE}.bak
  func_update_boto_config
  log_info "Updated credentials and config files"
}

# Alter the profile section titles for the boto version
func_update_boto_config () {
  sed 's/^\[/[profile /' ${CREDENTIALS_FILE} > ${BOTO_CONFIG_FILE}
}

# Gets a new session token using normal credentials and MFA
func_get_new_token () {
  local PROFILE_NAME=$1
  if [ -z ${PROFILE_NAME-} ]; then
    log_error "This fuction needs a profile name as an argument"
    exit 1
  fi

  func_get_value_from_profile_source "aws_access_key_id" "${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
  if [ -z ${RETVAL-} ]; then
    log_error "There are no IAM credential for profile '${PROFILE_NAME}'. Perhaps you meant to assume a role instead of getting credential directly?"
    exit 1
  fi


  log_info "Getting new STS session credentials for '${PROFILE_NAME}'"

  # Get a fresh mfa token
  if [ -n "${MFA_PROGRAM}" ]; then
    MFA_TOKEN=$(${MFA_PROGRAM} "${PROFILE_NAME}")
  else
    read -p "Enter the MFA code for ${PROFILE_NAME}: " -r
    if [ -z $REPLY ]; then
      echo "I need an MFA code to continue."
      exit 1
    fi
    MFA_TOKEN="${REPLY}"
  fi

  # Get a fresh sts session token
  func_get_value_from_profile_source "aws_access_key_id" "${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
  MASTER_KEY=${RETVAL}
  func_get_value_from_profile_source "mfa_id" "${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
  MFA_ID=${RETVAL}
  log_debug "Calling STS with mfa token ${MFA_TOKEN}, access_key ${MASTER_KEY}, and serial-number ${MFA_ID}"
  log_debug "${AWS_CLI} --profile ${PROFILE_NAME} sts get-session-token --serial-number ${MFA_ID} --token-code ${MFA_TOKEN}"
  JSON_SESSION_INFO=$(${AWS_CLI} --profile ${PROFILE_NAME} sts get-session-token --serial-number ${MFA_ID} --token-code ${MFA_TOKEN})
  log_debug "Json session info is:"
  log_debug "`echo $JSON_SESSION_INFO | jq '.[]'`"

  # Extract values from STS response
  AWS_ACCESS_KEY_ID=`echo ${JSON_SESSION_INFO} | jq '.Credentials.AccessKeyId' | tr -d '"'`
  AWS_SECRET_ACCESS_KEY=`echo ${JSON_SESSION_INFO} | jq '.Credentials.SecretAccessKey' | tr -d '"'`
  AWS_SESSION_TOKEN=`echo ${JSON_SESSION_INFO} | jq '.Credentials.SessionToken' | tr -d '"'`
  AWS_SESSION_TOKEN_EXPIRATION=`echo ${JSON_SESSION_INFO} | jq '.Credentials.Expiration' | tr -d '"'`
  log_debug "Set 'AWS_ACCESS_KEY_ID' to '${AWS_ACCESS_KEY_ID}'"
  log_debug "Set 'AWS_SECRET_ACCESS_KEY' to '${AWS_SECRET_ACCESS_KEY:0:25}<redacted>'"
  log_debug "Set 'AWS_SESSION_TOKEN' to '${AWS_SESSION_TOKEN:0:100}<redacted>'"
  log_debug "Set 'AWS_SESSION_TOKEN_EXPIRATION' to '${AWS_SESSION_TOKEN_EXPIRATION}'"

  return 0
}

# The song and dance of getting role credentials using the master profile
func_update_role_credentials () {
  ROLE_PROFILE="$1"
  func_get_value_from_profile_source "master_profile" "${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
  if [ -n "${RETVAL:-}" ]; then
    MASTER_PROFILE=${RETVAL}
  else
    MASTER_PROFILE="$DEFAULT_MASTER_PROFILE"
  fi
  if [ -z "${MASTER_PROFILE}" ]; then
    log_error "Couldn't find a user profile to use for role assumption."
    log_error "Either enter fill out the 'DEFAULT_MASTER_PROFILE' value in this script,"
    log_error "or add a 'master_profile = xxxxx' line to your role profile ("${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}")"
    exit 1
  fi
  # Remove the existing profile to remove old session tokens
  func_remove_profile_from_credentials_file "${ROLE_PROFILE}"
  # Add the regular profile so we can request session tokens
  func_append_profile_to_credentials_file "${ROLE_PROFILE}"
  # Now we can request a new token
  func_get_role_token "${ROLE_PROFILE}" "${MASTER_PROFILE}"
  # Update the regular profile with the session token version
  func_remove_profile_from_credentials_file "${ROLE_PROFILE}"
  func_append_sts_profile_to_credentials_file "${ROLE_PROFILE}"
  # Remove consecutive blank lines
  sed -i.bak '/./,/^$/!d' "${CREDENTIALS_FILE}"
  rm ${CREDENTIALS_FILE}.bak
  # Alter the profile section titles for the boto version
  sed 's/^\[/[profile /' ${CREDENTIALS_FILE} > ${BOTO_CONFIG_FILE}
  log_info "Updated credentials and config files"
}

# Gets a new role session token using the master-account credentials (probably an IAM token)
func_get_role_token () {
  # Sanity check
  if [ -z ${2-} ]; then
    log_error "This fuction needs two arguments"
    exit 1
  fi

  ROLE_PROFILE="$1"
  MASTER_PROFILE="$2"
  DATESTAMP=$(date +"%Y-%m-%d-%H-%M-%S")

  log_info "Getting new STS credentials for role '${ROLE_PROFILE}'"

  func_get_value_from_profile_source "account_id" "${CREDENTIALS_SOURCE_DIR}/${ROLE_PROFILE}"
  ROLE_ACCOUNT_ID=${RETVAL}
  func_get_value_from_profile_source "role_name" "${CREDENTIALS_SOURCE_DIR}/${ROLE_PROFILE}"
  ROLE_NAME=${RETVAL}

  ROLE_ARN="arn:aws:iam::${ROLE_ACCOUNT_ID}:role/${ROLE_NAME}"

  # Get a fresh sts session token
  log_debug "Calling STS using profile '${MASTER_PROFILE}' to assume role '${ROLE_ARN}'"
  set +e  # It's ok for the next line to fail; we can recover
  JSON_SESSION_INFO=$(${AWS_CLI} --profile ${MASTER_PROFILE} sts assume-role --role-arn ${ROLE_ARN} --role-session-name "${LOGNAME}-${DATESTAMP}")
  ret=$?
  set -e
  if ! [ $ret == 0 ]; then
    log_info "The master profile's temporary IAM credentials are expired. Renewing them..."
    log_info ""
    func_update_token "${MASTER_PROFILE}"
    log_info ""
    log_info "Renewed the master profile's credentials. Trying to get role credentials again."
    JSON_SESSION_INFO=$(${AWS_CLI} --profile ${MASTER_PROFILE} sts assume-role --role-arn ${ROLE_ARN} --role-session-name "${LOGNAME}-${DATESTAMP}")
  fi
  log_debug "Json session info is:"
  log_debug "``echo $JSON_SESSION_INFO | jq '.[]'``"

  # Extract values from STS response
  AWS_ACCESS_KEY_ID=`echo ${JSON_SESSION_INFO} | jq '.Credentials.AccessKeyId' | tr -d '"'`
  AWS_SECRET_ACCESS_KEY=`echo ${JSON_SESSION_INFO} | jq '.Credentials.SecretAccessKey' | tr -d '"'`
  AWS_SESSION_TOKEN=`echo ${JSON_SESSION_INFO} | jq '.Credentials.SessionToken' | tr -d '"'`
  AWS_SESSION_TOKEN_EXPIRATION=`echo ${JSON_SESSION_INFO} | jq '.Credentials.Expiration' | tr -d '"'`
  log_debug "Set 'AWS_ACCESS_KEY_ID' to '${AWS_ACCESS_KEY_ID}'"
  log_debug "Set 'AWS_SECRET_ACCESS_KEY' to '${AWS_SECRET_ACCESS_KEY:0:25}<redacted>'"
  log_debug "Set 'AWS_SESSION_TOKEN' to '${AWS_SESSION_TOKEN:0:100}<redacted>'"
  log_debug "Set 'AWS_SESSION_TOKEN_EXPIRATION' to '${AWS_SESSION_TOKEN_EXPIRATION}'"

  return 0
}

# Needed to clean out old profile info before added refreshed info
func_remove_profile_from_credentials_file () {
  local PROFILE_NAME=$1
  sed -i.bak -e '/./{H;$!d;}' -e 'x;/\['"${PROFILE_NAME}"'\]/d;' ${CREDENTIALS_FILE}
  rm ${CREDENTIALS_FILE}.bak
  log_debug "Removed profile '${PROFILE_NAME}' from ${CREDENTIALS_FILE}"
  return 0
}

# Adds a reguler profile to to the credentials file, plus session tokens
func_append_sts_profile_to_credentials_file () {
  local PROFILE_NAME=$1
  func_append_profile_without_creds_to_credentials_file "${PROFILE_NAME}"
  cat >> ${CREDENTIALS_FILE} <<-EOF
aws_access_key_id = ${AWS_ACCESS_KEY_ID}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY}
aws_session_token = ${AWS_SESSION_TOKEN}
aws_session_token_expiration = ${AWS_SESSION_TOKEN_EXPIRATION}
EOF
  log_debug "Appended STS tokens for ${PROFILE_NAME}"
  return 0
}

# Appends a profile (including AWS credentials) to profile
func_append_profile_to_credentials_file () {
  local PROFILE_NAME=$1
  local PROFILE_SOURCE_FILE="${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
  func_check_if_profile_source_valid "${PROFILE_SOURCE_FILE}"
  echo '' >> ${CREDENTIALS_FILE}
  cat ${PROFILE_SOURCE_FILE} >> ${CREDENTIALS_FILE}
  echo "### This profile section was auto-generated from '${PROFILE_SOURCE_FILE}' ###" >> ${CREDENTIALS_FILE}
  log_debug "Appended unaltered ${PROFILE_SOURCE_FILE}"
}

# Appends a profile (without AWS credentials) to profile
func_append_profile_without_creds_to_credentials_file () {
  local PROFILE_NAME=$1
  local PROFILE_SOURCE_FILE="${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
  func_check_if_profile_source_valid "${PROFILE_SOURCE_FILE}"
  echo '' >> ${CREDENTIALS_FILE}
  cat ${PROFILE_SOURCE_FILE} | sed -e '/aws_access_key_id/d' -e '/aws_secret_access_key/d' >> ${CREDENTIALS_FILE}
  echo "### This profile section was auto-generated from '${PROFILE_SOURCE_FILE}' ###" >> ${CREDENTIALS_FILE}
  log_debug "Appended unaltered ${PROFILE_SOURCE_FILE}"
}

# Simple helper for sanity checking that the profile source file exists and is sane
func_check_if_profile_source_valid ()
{
  if ! [ -f ${1} ]; then
    log_error "The credentials source (${1}) file doesn't exist"
    func_list_profiles
    exit 1
  fi
  if `grep '^\['"${1}"'\]$' ${1}`; then
    log_error "The profile heading '${1}' was not found in the file '${1}'"
    exit 1
  fi
}

# Check the type of profile file given
func_is_role_profile () {
  func_get_value_from_profile_source "role_name" "${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
  if [ -z "${RETVAL:-}" ]; then
    log_debug "No 'role_name' found in "${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}". Assuming this profile is a user profile."
    return 1
  else
    log_debug "'role_name' found in "${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}". Assuming this profile is a role profile."
    return 0
  fi
}

# Convert the contents of a profile section to a sourceable environment variable export file.
func_export_to_env_file () {
  PN=$1
  ENVFILE=$2
  cat ${CREDENTIALS_FILE} | sed -e '/./{H;$!d;}' -e 'x;/\['"${PN}"'\]/!d;' | sed -n 's/^region = \(.*\)/export AWS_DEFAULT_REGION=\1/p' > ${ENVFILE}
  cat ${CREDENTIALS_FILE} | sed -e '/./{H;$!d;}' -e 'x;/\['"${PN}"'\]/!d;' | sed -n 's/^account_id = \(.*\)/export AWS_ACCT=\1/p' >> ${ENVFILE}
  cat ${CREDENTIALS_FILE} | sed -e '/./{H;$!d;}' -e 'x;/\['"${PN}"'\]/!d;' | sed -n 's/^aws_access_key_id = \(.*\)/export AWS_ACCESS_KEY_ID=\1/p' >> ${ENVFILE}
  cat ${CREDENTIALS_FILE} | sed -e '/./{H;$!d;}' -e 'x;/\['"${PN}"'\]/!d;' | sed -n 's/^aws_secret_access_key = \(.*\)/export AWS_SECRET_ACCESS_KEY=\1/p' >> ${ENVFILE}
  cat ${CREDENTIALS_FILE} | sed -e '/./{H;$!d;}' -e 'x;/\['"${PN}"'\]/!d;' | sed -n 's/^aws_session_token = \(.*\)/export AWS_SESSION_TOKEN=\1/p' >> ${ENVFILE}
  cat ${CREDENTIALS_FILE} | sed -e '/./{H;$!d;}' -e 'x;/\['"${PN}"'\]/!d;' | sed -n 's/^mfa_id = \(.*\)/export AWS_MFA_SN=\1/p' >> ${ENVFILE}

  cat >> ${ENVFILE} << "EOF"

EOF
chmod 600 "${ENVFILE}"
}




#################
# Main

# Sanity checks
if [ -z ${2-} ]; then
  log_error "You need to pass an action type (token or awsenv) and a profile name as arguments"
  log_error ""
  log_error "Example:"
  log_error "   $0 token my-account-admin-role"
  log_error ""
  func_list_profiles
  exit 1
fi

ACTION_NAME="$1"
PROFILE_NAME="$2"

if ! [ -d ${CREDENTIALS_SOURCE_DIR} ]; then
  log_error "The credentials source (${CREDENTIALS_SOURCE_DIR}) dir doesn't exist"
  exit 1
fi

PROFILE_SOURCE_FILE="${CREDENTIALS_SOURCE_DIR}/${PROFILE_NAME}"
func_check_if_profile_source_valid ${PROFILE_SOURCE_FILE}

# Create a new credentials file if it's missing
if ! [ -f ${CREDENTIALS_FILE} ]; then
  log_info "${CREDENTIALS_FILE} doesn't exist. Creating a new one"
  for i in ${CREDENTIALS_SOURCE_DIR}/*; do
    cat ${i} >> ${CREDENTIALS_FILE}
    echo '' >> ${CREDENTIALS_FILE}
    echo '' >> ${CREDENTIALS_FILE}
  done
  log_info "${CREDENTIALS_FILE} initialized."
fi


if func_is_role_profile; then
  func_update_role_credentials "${PROFILE_NAME}"
else
  AWS_SESSION_TOKEN_EXPIRATION=$(sed -e '/./{H;$!d;}' -e 'x;/\['"${PROFILE_NAME}"'\]/!d;' ${CREDENTIALS_FILE} | sed -En 's/aws_session_token_expiration = (.*)/\1/p')

  # If a session token doesn't exist, get a new one
  if [ -z ${AWS_SESSION_TOKEN_EXPIRATION} ]; then
    log_info "No session found in ${CREDENTIALS_FILE}. Creating a new one."
    func_update_token "${PROFILE_NAME}"

  else
  # If a token already exists, check if it's expired or close to expiring
    log_info "Checking if cached token is near or past expiration"
    log_debug "Found '${AWS_SESSION_TOKEN_EXPIRATION}' in ${CREDENTIALS_FILE} for profile ${PROFILE_NAME}"
    CURRENT_TIME_EPOCH=`date -j "+%s"`
    AWS_SESSION_TOKEN_EXPIRATION_EPOCH=`date -j -f "%Y-%m-%dT%H:%M:%SZ" "${AWS_SESSION_TOKEN_EXPIRATION}" "+%s"`
    AWS_SESSION_TOKEN_REFRESH_EPOCH=`date -j -f "%Y-%m-%dT%H:%M:%SZ" -v "-${TOKEN_PREEXPIRATION_HOURS}H" "${AWS_SESSION_TOKEN_EXPIRATION}" "+%s"`
    # If the session token has expired or is close to expiring, get a new one
    if [[ $AWS_SESSION_TOKEN_REFRESH_EPOCH < $CURRENT_TIME_EPOCH ]]; then
      log_info "The session token is no longer fresh (expires in $(((${AWS_SESSION_TOKEN_EXPIRATION_EPOCH} - ${CURRENT_TIME_EPOCH} ) / 60)) minutes). Getting a fresh one"
      func_update_token "${PROFILE_NAME}"
    else
      # other wise tell the user how long they have before it will be refreshed
      REFRESH_SEC=$(((${AWS_SESSION_TOKEN_REFRESH_EPOCH} - ${CURRENT_TIME_EPOCH}) % 60 ))
      REFRESH_MIN=$(((${AWS_SESSION_TOKEN_REFRESH_EPOCH} - ${CURRENT_TIME_EPOCH}) / 60 % 60))
      REFRESH_HR=$(((${AWS_SESSION_TOKEN_REFRESH_EPOCH} - ${CURRENT_TIME_EPOCH}) / 3600))
      EXPIRE_SEC=$(((${AWS_SESSION_TOKEN_EXPIRATION_EPOCH} - ${CURRENT_TIME_EPOCH}) % 60))
      EXPIRE_MIN=$(((${AWS_SESSION_TOKEN_EXPIRATION_EPOCH} - ${CURRENT_TIME_EPOCH}) / 60 % 60))
      EXPIRE_HR=$(((${AWS_SESSION_TOKEN_EXPIRATION_EPOCH} - ${CURRENT_TIME_EPOCH}) / 3600))
      log_info "Everything looks good. Reusing existing session token (fresh for ${REFRESH_HR}:${REFRESH_MIN}:${REFRESH_SEC}, expires in ${EXPIRE_HR}:${EXPIRE_MIN}:${EXPIRE_SEC})"
    fi
  fi
fi

if [ "${ACTION_NAME}" == "awsenv" ]; then
  # Save the profile credentials to a file that can be exported by the shell function calling this
  func_export_to_env_file "${PROFILE_NAME}" "${AWS_DIR}/current-env.txt"
fi

exit 0
