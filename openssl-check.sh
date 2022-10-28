#!/bin/bash
# License GPL
# Copyright 2022 Omkhar Arasaratnam 

for FILE in `find / -type f -executable -print`
do
  SSL=""
  SSL=`ldd ${FILE} 2> /dev/null | grep -i libssl.so.3`
  EXIT=$?
  if [ ${EXIT} -eq 0 ]
  then
    echo "${FILE} may be dynamically linked to openssl-3.x"
  fi
done
