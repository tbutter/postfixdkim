#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Set the domain and hostname from environment variables
if [ -z "$MAIL_DOMAIN" ] || [ -z "$MAIL_HOSTNAME" ]; then
    echo "MAIL_DOMAIN and MAIL_HOSTNAME environment variables are not set."
    echo "Using default values: example.com and mail.example.com"
    MAIL_DOMAIN="example.com"
    MAIL_HOSTNAME="mail.example.com"
fi

# Set mailname
echo "$MAIL_DOMAIN" > /etc/mailname

# Update Postfix main.cf with the correct domain and hostname
postconf -e "myhostname = $MAIL_HOSTNAME"
postconf -e "mydomain = $MAIL_DOMAIN"
postconf -e "myorigin = \$mydomain"
postconf -e "smtp_tls_security_level = may"

if [ -n "$SMTP_BIND_ADDRESS" ]; then
    postconf -e "smtp_bind_address = $SMTP_BIND_ADDRESS"
fi

if [ -z "$DKIM_SELECTOR" ]; then
    DKIM_SELECTOR="default"
fi

if [ "$USE_LETSENCRYPT" = "true" ]; then
    CERT_DIR="/etc/letsencrypt/live/$MAIL_HOSTNAME"
    CERT_FILE="$CERT_DIR/fullchain.pem"
    if [ -f "$CERT_FILE" ]; then
        echo "Checking Let's Encrypt certificate for renewal..."
        if ! openssl x509 -in "$CERT_FILE" -checkend $((30 * 24 * 60 * 60)); then
            echo "Certificate is due for renewal. Renewing..."
        else
            echo "Certificate is not due for renewal."
        fi

        postconf -e "smtp_tls_cert_file = $CERT_DIR/fullchain.pem"
        postconf -e "smtp_tls_key_file = $CERT_DIR/privkey.pem"
        postconf -e "smtp_tls_CAfile = $CERT_DIR/chain.pem"
    else
        echo "Let's Encrypt certificate not found in $CERT_DIR. Skipping TLS configuration."
    fi
fi

# Update OpenDKIM configuration
sed -i "s/Domain .*/Domain $MAIL_DOMAIN/" /etc/opendkim.conf
sed -i "s/KeyFile .*/KeyFile \/etc\/opendkim\/keys\/$DKIM_SELECTOR.private/" /etc/opendkim.conf
sed -i "s/Selector .*/Selector $DKIM_SELECTOR/" /etc/opendkim.conf
sed -i "s/.*@example.com .*/\*@$MAIL_DOMAIN $DKIM_SELECTOR._domainkey.$MAIL_DOMAIN/" /etc/opendkim/SigningTable
sed -i "s/default._domainkey.example.com .*/$DKIM_SELECTOR._domainkey.$MAIL_DOMAIN $MAIL_DOMAIN:$DKIM_SELECTOR:\/etc\/opendkim\/keys\/$DKIM_SELECTOR.private/" /etc/opendkim/KeyTable
sed -i "s/example.com/$MAIL_DOMAIN/" /etc/opendkim/ExternalIgnoreList


# Generate DKIM keys if they don't exist
if [ ! -f /etc/opendkim/keys/$DKIM_SELECTOR.private ]; then
    echo "Generating DKIM keys..."
    mkdir -p /etc/opendkim/keys
    chown -R opendkim:opendkim /etc/opendkim/keys
    opendkim-genkey -s $DKIM_SELECTOR -d $MAIL_DOMAIN -D /etc/opendkim/keys
    chown opendkim:opendkim /etc/opendkim/keys/$DKIM_SELECTOR.private
    echo "DKIM keys generated."
    echo "Add the following TXT record to your DNS:"
    cat /etc/opendkim/keys/$DKIM_SELECTOR.txt
fi

# Create SASL users
if [ -f /etc/postfix/sasl_users ]; then
    echo "Loading SASL users from /etc/postfix/sasl_users"
    while read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^#.*$ ]] && continue
        [ -z "$line" ] && continue
        if [[ "$line" == *:* ]]; then
            user=${line%%:*}
            password=${line#*:}
        elif [[ "$line" == *" "* ]]; then
            user=${line%% *}
            password=${line#* }
        else
            continue
        fi
        echo "Creating SASL user: $user"
        echo "$password" | saslpasswd2 -p -c -u "$MAIL_DOMAIN" "$user"
    done < /etc/postfix/sasl_users
    chown postfix:postfix /etc/sasldb2
    chmod 600 /etc/sasldb2
elif [ -n "$SASL_USER" ] && [ -n "$SASL_PASSWORD" ]; then
    echo "Creating SASL user: $SASL_USER"
    echo "$SASL_PASSWORD" | saslpasswd2 -p -c -u "$MAIL_DOMAIN" "$SASL_USER"
    chown postfix:postfix /etc/sasldb2
    chmod 600 /etc/sasldb2
fi

chown 600 /etc/postfix/master.cf
# Start OpenDKIM and Postfix
echo "Starting OpenDKIM..."
service opendkim start
echo "Starting Postfix..."
service postfix start

# Keep the container running
echo "Postfix and OpenDKIM are running. Tailing mail log..."
touch /var/log/mail.log
tail -f /var/log/mail.log
