#!/bin/env bash
#ssh eton@xyzp-Mac-Studio.local #192.168.0.127
echo "danielMo zsh "
ssh2host.sh xyzp-Mac-Studio.local
avahi-browse -art|grep -m 1 "xyzp-Mac-Studio.local" -A 2
