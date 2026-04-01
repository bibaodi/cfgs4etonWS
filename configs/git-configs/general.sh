#!/bin/bash

set -e

_FILE_DIR=$(dirname "$(readlink -f "$0")")
_colorLib="${_FILE_DIR}/../../scripts-bash/03-color-msg.sh"
chmod +x ${_colorLib}
source ${_colorLib}

function listConfigs(){
	GREEN_MSG "\nlist all configs\n"
	git config list
}

listConfigs;

RED_MSG "set auto upsteam"
git config push.autoSetupRemote true
listConfigs;
