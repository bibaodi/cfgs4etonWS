_path=${1:-/tmp}

find "${_path}" -type f ! \( -name "*.json" -o -name "*.png" \)

find "${_path}" -type f | grep -Pv '\.(json|png)$'
