#!/bin/env bash

_localfile=${1:-nothing}

test ! -f ${_localfile} && (echo "file [${_localfile}] not exsit, exit." ; exit 0;)

read -r -p "store '$_localfile' to S3 Thyroid? (y/n): " ans

test ${ans} != 'y' && exit 0


aws s3 cp ${_localfile} s3://ftp-huaxia-200420/usData-FormalRelease/10lastVersion-LocalAll/Thyroid/

echo "[$0] finished..."
