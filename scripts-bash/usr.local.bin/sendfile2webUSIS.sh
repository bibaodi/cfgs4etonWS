CMD="scp -i ~/.aws/aws-labelme-ec.pem ${1:-nothing} ubuntu@52.81.61.18:/tmp"

read -p "run [${CMD}]? y/n" ans

test ${ans} == 'y' &&  eval ${CMD}
