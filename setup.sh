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
  echo "'${PARENTDIR}' doesn't exist. Creating it..."
  mkdir -p "${PARENTDIR}"
fi

cd "${PARENTDIR}"
git clone https://github.com/seren/aws-token-refresh.git
cd aws-token-refresh
DIR="${PARENTDIR}/aws-token-refresh"

mkdir -p "${HOME}/.aws/aws-profiles"
chmod 700 "${HOME}/.aws/aws-profiles"

cp profile-additions.source_me profile-additions.source_me.bak
# shellcheck disable=2016
echo 'AWS_SCRIPTS_DIR="${HOME}/'"${DIR}" > profile-additions.source_me
sed '1d' profile-additions.source_me.bak >> profile-additions.source_me
rm profile-additions.source_me.bak

echo "Adding '. "'"'"${DIR}"'"'"/profile-additions.source_me' to ${HOME}/.bash_login"
echo "If you don't use bash, add it to the your shell's login file."
echo '. "'"${DIR}"'/profile-additions.source_me"' >> "${HOME}/.bash_login"

open .
