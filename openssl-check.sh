#!/usr/bin/env bash
# License GPL
# Copyright 2022 Omkhar Arasaratnam
#   sexified by Rob Dailey

function cleanup_kids { 
  for job in $(jobs -lp); do
     kill -9 ${job}
  done
  exit 1
}
trap cleanup_kids INT

DEPTH=2
MAX_RUNNING=0
PREV=""
LDD=""
LDD_FLAGS=""
FIND=""
BASE_EXCLUDES=""
declare -A BASE_EXCLUDES

os=$(uname | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')

while getopts c:d: cmd_flag; do
  case "${cmd_flag}" in
    c) MAX_RUNNING=${OPTARG};;
    d) DEPTH=${OPTARG};;
  esac
done

if [[ "${MAX_RUNNING}" == 0 ]]; then
  MAX_RUNNING=$(cat /proc/cpuinfo 2>/dev/null | grep -c processor)

  if [[ "${MAX_RUNNING}" == 0 ]]; then
    MAX_RUNNING=$(sysctl hw.ncpu 2>/dev/null | tr -cd '[:digit:]')
    MAX_RUNNING=$(( ${MAX_RUNNING:-"4"} / 4 ))
    if [[ "${MAX_RUNNING}" -lt "4" ]]; then
      MAX_RUNNING=4  # seems to be optimal min
    fi
  fi
fi

if [[ "${DEPTH}" -gt 2 ]]; then
  echo "you probably don't want to do > 2 (default). [enter to continue]"
  read
fi

echo "Running with: [${MAX_RUNNING}]:Jobs [${DEPTH}]:Depth"

if [[ ${UID} -ne 0 ]]; then
  echo "Not running as root, we may not be able to read all binaries on the system [enter to continue]"
  read
fi

if [[ "${os}" == 'linux' ]];then 
  LDD=$(which ldd)
  WHICH_LDD_EXIT=$?
  LIB="libssl.so.3"
elif [[ "${os}" == *"bsd"* ]]; then
  LDD=$(which ldd)
  WHICH_LDD_EXIT=$?
  LIB="libssl.so.3"
  LOCALS_ONLY="-fstype local"
elif [[ "${os}" == 'darwin' ]]; then
  LDD=$(which otool)
  WHICH_LDD_EXIT=$?
  LDD_FLAGS="-L"
  LIB="libssl.3.dylib"
  LOCALS_ONLY="-fstype local"
else
  echo "unsupported OS [${os}]"
  exit 1
fi

if [[ "${WHICH_LDD_EXIT}" -ne 0 ]]; then
  echo "Couldn't find ldd, exiting"
  exit 1
fi


FIND=$(which find)
WHICH_FIND_EXIT=$?
if [[ ${WHICH_FIND_EXIT} -ne 0 ]]; then
  echo "Couldn't find find, exiting"
  exit 1
fi


function run_parallel {

  while read -r file_path; do
    ldd_out=$(${LDD} ${LDD_FLAGS} ${file_path} 2>/dev/null)
    if [[ ${ldd_out} == *"${LIB}"* ]]; then
      echo "'${file_path}' may be dynamically linked to openssl-3.x"
    fi
  done < <(${FIND} "${1}" ${@:2} -type f -perm -a=x -print 2>/dev/null)

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
  _BASE="${_BASE#"${_BASE}%%[![:space:]]*}"}" 

  if [[ "${PREV}" == "${dir_path}" ]];  then
    (run_parallel ${dir_path} -maxdepth 1 \( ${BASE_EXCLUDES[${_BASE}]} \) -prune -o ! -type d) &
    unset ${BASE_EXCLUDES[${_BASE}]}  # cleanup memory
  else
    # not a top level path
    (run_parallel ${dir_path}) &

  fi
  BASE_EXCLUDES[${_BASE}]="${BASE_EXCLUDES[${_BASE}]} -path \"${dir_path}\" -o"
  PREV=$(dirname ${dir_path})

  _skip_tree=""
  for _skip_base in "${split_path[@]}"; do
      _skip_tree="${_skip_tree} ${_skip_base}"
      _skip_tree="${_skip_tree#"${_skip_tree}%%[![:space:]]*}"}" 
      BASE_EXCLUDES[${_skip_tree}]="${BASE_EXCLUDES[${_skip_tree}]} ${BASE_EXCLUDES[${_BASE}]}"
  done

  SELF_RUNNING=$(jobs | grep -c ' Running ')
  while [[ "$SELF_RUNNING" -ge "${MAX_RUNNING}" ]]; do
    SELF_RUNNING=$(jobs | grep -c ' Running ')
    wait -n
  done

done < <(find / -maxdepth ${DEPTH} \( -path "/proc" -o -path "/System/Volumes" \) -prune -o ${MAC_LOCALS_ONLY} -type d -print 2>/dev/null | sort -r)

# catch any leftover files
while read -r dir_path; do
  run_parallel ${dir_path}
done < <(find / -maxdepth 1 ! -type d 2>/dev/null )

wait
echo -e "\n[fin]"
