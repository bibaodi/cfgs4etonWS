function listConfigs(){
	echo "list all configs"
	git config list
}

listConfigs;

echo "set auto upsteam"
git config push.autoSetupRemote true
listConfigs;
