# Use Ubuntu 20.04 as the base image
FROM ubuntu:20.04

# Set environment variables to non-interactive to avoid prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Install Postfix, OpenDKIM, and other necessary tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    postfix \
    opendkim \
    opendkim-tools \
    sasl2-bin \
    procps \
    certbot \
    && rm -rf /var/lib/apt/lists/*

# Create necessary directories for OpenDKIM
RUN mkdir -p /etc/opendkim/keys

# Copy Postfix and OpenDKIM configuration files
COPY main.cf /etc/postfix/main.cf
COPY master.cf /etc/postfix/master.cf
COPY opendkim.conf /etc/opendkim.conf
COPY KeyTable /etc/opendkim/KeyTable
COPY SigningTable /etc/opendkim/SigningTable
COPY ExternalIgnoreList /etc/opendkim/ExternalIgnoreList

# Copy the startup script and make it executable
COPY startup.sh /usr/local/bin/startup.sh
RUN chmod +x /usr/local/bin/startup.sh

# Expose the SMTP port
EXPOSE 25

# Set the startup script as the entrypoint
CMD ["/usr/local/bin/startup.sh"]
