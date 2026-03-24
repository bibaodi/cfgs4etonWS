rsync -e 'ssh -i ~/.aws/aws-labelme-ec.pem' -avzP ubuntu@54.223.40.69:~/backups/*.sh ./webuis-fc2.backups/
