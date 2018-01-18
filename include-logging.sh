#!/usr/bin/env bash

XTRACE=${XTRACE:-0}

declare -A log_levels
log_levels=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

function loggable_timestamp {
  date "+%F %T"
}

function check_log_level {
  local global_log_level_name=${LOG_LEVEL:-INFO}
  local global_log_level=${log_levels[$global_log_level_name]}
  local event_log_level=${log_levels[$1]}
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
