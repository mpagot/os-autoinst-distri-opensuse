# Use the specified image
FROM registry.opensuse.org/opensuse/tumbleweed:latest

# Copy the script into the image
COPY .devcontainer/install-dependency.sh /run/install-dependency.sh

# Make the script executable
RUN chmod +x /run/install-dependency.sh

# Run the script
RUN /run/install-dependency.sh