#!/usr/bin/env bash
# License GPL
# Copyright 2022 Omkhar Arasaratnam
#   Made sexier by Rob Dailey

MAX_RUNNING=$(cat /proc/cpuinfo0 2>/dev/null | grep -c processor)
if [[ ${MAX_RUNNING} == 0 ]]; then
  MAX_RUNNING=$(sysctl hw.ncpu 2>/dev/null | tr -cd '[:digit:]')
  MAX_RUNNING=$((${MAX_RUNNING:-"4"} / 2))
fi
echo "Running with [${MAX_RUNNING}] Jobs"

if [ ${UID} -ne 0 ]
then
  echo "Not running as root, we may not be able to read all binaries on the system [enter to continue]"
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

  ${FIND} ${1} ${@:2} -type f -perm -a=x -print0 2>/dev/null |
     xargs -0 -I FILE_NAME sh -c "${LDD} \"FILE_NAME\" 2>/dev/null | grep -Iq libssl.so.3 2>/dev/null && echo \"FILE_NAME may be dynamically linked to openssl-3.x\"" &

  SELF_RUNNING=$(jobs | wc -l | sed 's/[ \t]*//')
  if [[ $SELF_RUNNING -ge ${MAX_RUNNING} ]]; then
    wait -n
  fi

}

PREV=""
# hit all the dirs
while read -r dir_path; do
  if [[ "${dir_path}" == "/" ]]; then
      continue
  fi
  if [[ "${PREV}" == "${dir_path}" ]];  then
      run_parallel ${dir_path} -maxdepth 1 ! -type d
  else
      run_parallel ${dir_path}
  fi
  PREV=$(dirname ${dir_path})
done < <(find / -maxdepth 2 -type d 2>/dev/null | sort -r)

# catch any leftover files
while read -r dir_path; do
  run_parallel ${dir_path}
done < <(find / -maxdepth 1 ! -type d 2>/dev/null)

wait
echo -e "\n[fin]"
