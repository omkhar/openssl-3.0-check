#!/bin/bash
# License GPL
# Copyright 2022 Omkhar Arasaratnam 

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

for FILE in `${FIND} / -type f -executable -print`
do
  ${LDD} ${FILE} 2> /dev/null | grep -i "libssl.so.3" &> /dev/null
  EXIT=$?
  if [ ${EXIT} -eq 0 ]
  then
    echo "${FILE} may be dynamically linked to openssl-3.x"
  fi
done
