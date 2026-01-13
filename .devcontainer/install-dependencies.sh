# Generic update
zypper dup -y

# dependency suggested in the CONTRIBUTING.md
zypper in -y os-autoinst-distri-opensuse-deps perl-JSON-Validator gnu_parallel

# other dependency that are needed
zypper in -y make git vim gcc-c++ libxml2-devel libssh2-devel libexpat-devel dbus-1-devel python311 python311-devel python311-yamllint python311-PyYAML perl-App-cpanminus perl-Code-TidyAll

# step suggested by the CONTRIBUTING.md
echo "#########################################"
pwd

echo "###### CODESPACE_VSCODE_FOLDER: ${CODESPACE_VSCODE_FOLDER} #######"
pwd
ls -lai .
ls -lai ${CODESPACE_VSCODE_FOLDER}
ls -lai /workspaces || echo "### LATER ###"
#cd ${CODESPACE_VSCODE_FOLDER}
#make prepare