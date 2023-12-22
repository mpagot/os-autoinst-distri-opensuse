# Use the specified image
FROM registry.opensuse.org/opensuse/tumbleweed:latest

# Copy the script into the image
COPY install-dependencies.sh /tmp/install-dependencies.sh

# Run the script, additional repo is needed by perl-Perl-LanguageServer
RUN zypper --non-interactive --quiet addrepo https://download.opensuse.org/repositories/devel:languages:perl/openSUSE_Tumbleweed/devel:languages:perl.repo \
    && zypper --gpg-auto-import-keys ref \
    && /tmp/install-dependencies.sh


ARG USERNAME=node
ARG PASSWORD=password
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN zypper -n install shadow sudo \
    && groupadd --gid $USER_GID $USERNAME \
    && useradd -u $USER_UID -g $USER_GID -m $USERNAME \
    && echo "$USERNAME:$PASSWORD" | chpasswd \
    && echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers \
    && chmod 0440 /etc/sudoers

USER $USERNAME