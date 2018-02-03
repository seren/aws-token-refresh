#!/usr/bin/env bash

set -ueo pipefail
set -x

read -p "Where do you want to store the scripts? (ex. ~/Documents/aws-scripts) " -r
if [[ -n $REPLY ]]; then
  PARENTDIR="$( unset CDPATH && cd "${REPLY/#\~/$HOME}" && pwd -P )"
fi

if ! [ -d "${PARENTDIR}" ]; then
  echo ""${PARENTDIR}" doesn't exist. Creating it..."
  mkdir -p "${PARENTDIR}"
fi

cd "${PARENTDIR}"
git clone https://github.com/seren/aws-token-refresh.git
cd aws-token-refresh
DIR="${PARENTDIR}/aws-token-refresh"

mkdir -p ${HOME}/.aws/aws-profiles
chmod 700 ${HOME}/.aws/aws-profiles

cp profile-additions.sh profile-additions.bak
echo 'AWS_SCRIPTS_DIR="${HOME}/'"${DIR}" > profile-additions.sh
sed '1d' profile-additions.bak >> profile-additions.sh
rm profile-additions.bak

echo 'source "'"${DIR}"'/profile-additions.sh"' >> ${HOME}/.profile
# echo 'source "'"${DIR}"'/profile-additions.sh"' >> ${HOME}/.bash_login

open .
