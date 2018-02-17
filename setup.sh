#!/usr/bin/env bash

set -ueo pipefail
set -x

REPLY=''
while [[ -z $REPLY ]]; do
  read -p "Where do you want to store the scripts? (ex. ~/Documents/aws-scripts) " -r
  if [[ -z $REPLY ]]; then
    echo "You need to enter something."
  else
    PARENTDIR="$( unset CDPATH && cd "${REPLY/#\~/$HOME}" && pwd -P )"
  fi
done

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

echo "Adding 'source "'"'"${DIR}"'"'"/profile-additions.sh' to ${HOME}/.bash_login"
echo "If you don't use bash, add it to the your shell's login file."
echo 'source "'"${DIR}"'/profile-additions.sh"' >> ${HOME}/.bash_login

open .
