# Use the specified image
FROM registry.opensuse.org/opensuse/tumbleweed:latest

# Copy the script into the image
COPY . /tmp/

# Make the script executable
RUN chmod +x /tmp/install-dependency.sh

# Run the script
RUN /run/install-dependency.sh
#RUN zypper dup -y
#RUN zypper lr
#RUN zypper in -y os-autoinst-distri-opensuse-deps perl-JSON-Validator gnu_parallel || echo "---zypper failure---"
#RUN zypper in -y make git vim gcc-c++ libxml2-devel libssh2-devel libexpat-devel dbus-1-devel python311 python311-devel python311-yamllint python311-PyYAML perl-App-cpanminus perl-Code-TidyAll
#RUN echo "---###---   ---###---"
#RUN pwd
#cd ${CODESPACE_VSCODE_FOLDER}
#make prepare