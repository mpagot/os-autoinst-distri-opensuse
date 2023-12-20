# Use the specified image
FROM registry.opensuse.org/opensuse/tumbleweed:latest

# Copy the script into the image
COPY install-dependencies.sh /tmp/install-dependencies.sh

# Run the script
RUN /tmp/install-dependencies.sh


ARG USERNAME=node
ARG USER_UID=1000
ARG USER_GID=$USER_UID

#RUN useradd podman; \
#echo podman:10000:5000 > /etc/subuid; \
#echo podman:10000:5000 > /etc/subgid;

# Create the user
RUN zypper -n install shadow sudo \
    && groupadd --gid $USER_GID $USERNAME \
    && useradd -u $USER_UID -g $USER_GID -m $USERNAME \
    && echo "$USERNAME:password" | chpasswd \
    && echo "$USERNAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers \
    && chmod 0440 /etc/sudoers

USER $USERNAME