#!/bin/env bash
while true; do i
	aws ec2 start-instances --instance-ids --region cn-northwest-1 i-0eb714f9141b66c65 ; 
	if [ $? -eq 0 ]; then 
		break; 
	else 
		sleep 2; 
	fi; 
done
