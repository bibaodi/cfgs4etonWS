_SDIR="${1:-nothing}"

_SDIR="/train/history_train/${_SDIR}"

test ! -e "${_SDIR}" && echo "Usage: app ResultName{res_surpressFP_mul_thyNoduGlandv09.N13_20260515T1628_sz224}" && exit 0;

ls ./train-logs

find ${_SDIR} -name "*.log" -o -name "*.txt" -o -name "*.csv"|xargs -I {} cp '{}' ./train-logs/

ls ./train-logs


