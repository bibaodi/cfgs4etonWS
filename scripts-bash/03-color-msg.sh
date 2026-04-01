#!/bin/bash
RED='\033[0;31m'
GREEN='\033[0;32m'
NEWGREEN='\033[1;5;47;32m' #it is great in composition.
NOCOLOR='\033[0m'

function PR_MSG() {
        COL=${1:-GREEN}
        STR=${2:-ColorString}
        printf "${COL}${STR}${NOCOLOR}"
}


function GREEN_MSG(){
        local MSG=${@:-MsgString}
        PR_MSG ${GREEN} "${MSG}"
}

function RED_MSG(){
        local MSG=${@:-MsgString}
        PR_MSG ${RED} "${MSG}"
}

function checkResult() {
        local ret=${1:-FAILED} 
        #test ${ret} -eq 0 && GREEN_MSG "...[OK]\n" 
        #test ${ret} -ne 0 && RED_MSG "...[FAILED]\n" || exit -1;
        if test ${ret} -eq 0 ; then
                GREEN_MSG "...[OK]\n";
        else 
                RED_MSG "...[FAILED]\n";
        fi
        return ${ret}
}


###end


