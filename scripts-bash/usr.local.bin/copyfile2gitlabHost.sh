#!/bin/env bash

sfile=${1:-empty}
test "empty" == ${sfile} && echo -e "Usage:$0 path-to-file\n" && exit 0


read -p "want send file[${sfile}] to 244(gitlabsrv)?y/n" ans

test 'y' != ${ans:-xx} && exit 0

rsync -azvP "${sfile}" xin1u@192.168.0.244:/tmp/

echo "done..."

