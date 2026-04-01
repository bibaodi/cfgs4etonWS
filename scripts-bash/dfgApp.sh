#!/bin/bash
#eton@240914 using add LD_LIBRARY_PATH as function

BASE_DIR=$(dirname "$(readlink -f "$0")")
source "${BASE_DIR}/02-addLocalRPath.sh"
#source "${BASE_DIR}/03-color-msg.sh"

IS_PRODUCTION=${SIHO_PROD:-0}
if test ${IS_PRODUCTION} -eq 0;then 
	echo "In Development ENV, set unlimited..."
	ulimit -c unlimited
else
	echo "In Production ENV, set ulimit=0"
	ulimit -c 0 
fi

_APP="${SIHOBIN_DIR}/${AppName}"

chmod +x ${_APP} 
${_APP} "$@"
AppReturn=$?
chmod -x ${_APP} 
echo "<$0> run return=[$AppReturn] end."
exit $AppReturn

