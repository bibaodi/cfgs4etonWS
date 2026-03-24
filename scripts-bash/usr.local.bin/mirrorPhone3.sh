#!/bin/env bash
_usage='startScrcpy.sh -s 2115d2a6'

cd ~/42workspace.link/10-ExtSrcs/scrcpy-linux-x86_64-latest/ 
adb devices
echo "params(use -s 2115d if multidevices conntected)=[${@}]"
#INFO: ADB device found:
#INFO:     -->   (usb)  2115d2a6                        device  24069RA21C
#INFO:           (usb)  R5CRA193F5W                     device  SM_N9860
_bestOps='--stay-awake --window-title "EtonPhon" --turn-screen-off --no-audio --push-target=/sdcard/Download/2503BuickSales'
_bestOps2='--window-title "EtonPhon" --otg '
CMD="./scrcpy ${_bestOps}"
test $# -gt 0 && CMD="${CMD} ${@} --"
echo "CMD=[${CMD}]"
eval ${CMD}


printf "Usage:\n\t${_usage};\n\n"
sync
