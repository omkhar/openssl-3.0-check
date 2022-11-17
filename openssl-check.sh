#!/usr/bin/env bash
# License GPL
# Copyright 2022 Omkhar Arasaratnam
#   - made sexier by rob dailey

DEPTH=${1:-2}
PREV=""
BASE_EXCLUDES=""
declare -A BASE_EXCLUDES

PID=$$
echo "PID: ${PID}"

MAX_RUNNING=$(cat /proc/cpuinfo0 2>/dev/null | grep -c processor)
if [[ ${MAX_RUNNING} == 0 ]]; then
  MAX_RUNNING=$(sysctl hw.ncpu 2>/dev/null | tr -cd '[:digit:]')
  MAX_RUNNING=$((${MAX_RUNNING:-4} / 2))
fi
echo "Running with [${MAX_RUNNING}] Jobs"

if [ ${UID} -ne 0 ]
then
        echo "Not running as root, we may not be able to read all binaries on the system [enter to continue]"
        read
fi

if [ ${DEPTH} -gt 2 ]; then
    echo "Don't run more than 2 deep unless you know something special ... it gets slower (currently) [enter to continue]"
    read
fi

LDD=`which ldd`
EXIT=$?
if [ ${EXIT} -ne 0 ]
then
        echo "Couldn't find ldd, exiting"
        exit 1
fi

FIND=`which find`
EXIT=$?
if [ ${EXIT} -ne 0 ]
then
        echo "Couldn't find find, exiting"
        exit 1
fi


function run_parallel {

  SELF_RUNNING=$(jobs | wc -l | tr -cd '[:digit:]')
  if [[ $SELF_RUNNING -ge ${MAX_RUNNING} ]]; then
    wait -n
  fi

  ${FIND} ${1} ${@:2} -type f -perm -a=x -print0 2>/dev/null |
      xargs -0 -I FILE_NAME sh -c "(${LDD} \"FILE_NAME\" 2>/dev/null | grep -q libssl.so.3 2>/dev/null) && echo \"FILE_NAME may be dynamically linked to openssl-3.x\"" &

}

# hit all the dirs
while read -r dir_path; do
  if [[ "${dir_path}" == "/" ]]; then
      continue
  fi

  # get our hash key
  IFS='\/' read -ra split_path <<< "${dir_path}"
  unset split_path[0] # clean null
  _BASE="${split_path[@]:0:${DEPTH}+1}" # we index at 0
  _BASE=$(sed -e 's/^[[:space:]]*//'<<<"${_BASE}")

  if [[ "${PREV}" == "${dir_path}" ]];  then
      run_parallel ${dir_path} -maxdepth 1 ! -type d ${BASE_EXCLUDES[${_BASE}]}
  else
      # not a top level path
      run_parallel ${dir_path}

  fi
  BASE_EXCLUDES[${_BASE}]="${BASE_EXCLUDES[${_BASE}]} -name \"${dir_path}\" -prune -o"
  PREV=$(dirname ${dir_path})

  _skip_tree=""
  for _skip_base in "${split_path[@]}"; do
      _skip_tree="${_skip_tree} ${_skip_base}"
      _skip_tree=$(sed -e 's/^[[:space:]]*//'<<<"${_skip_tree}")
      BASE_EXCLUDES[${_skip_tree}]="${BASE_EXCLUDES[${_skip_tree}]} ${BASE_EXCLUDES[${_BASE}]}"
  done

done < <(find / -maxdepth ${DEPTH} -type d -name "/proc" -prune -o -print 2>/dev/null | sort -r)

# catch any leftover files
while read -r dir_path; do
  run_parallel ${dir_path}
done < <(find / -maxdepth 1 ! -type d 2>/dev/null )

wait
echo -e "\n[fin]"
