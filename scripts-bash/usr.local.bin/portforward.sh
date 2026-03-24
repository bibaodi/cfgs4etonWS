cert_file="${HOME}/.aws/aws-labelme-ec.pem"
#ssh -i ${cert_file} -Y -o ServerAliveInterval=3 ubuntu@54.223.40.69
_port=${1:-5001}
echo "port forward to ${_port}"
ssh -i ${cert_file} -Y -o ServerAliveInterval=3 -N -L ${_port}:localhost:${_port} ubuntu@54.223.40.69


echo "done..."
