# Postfix with OpenDKIM Docker Image

This repository contains the necessary files to build a Docker image with Postfix and OpenDKIM for an outgoing SMTP server.

## Build the Image

To build the Docker image, run the following command in the root of the repository:

```bash
podman build -t postfix-dkim .
```

## Run the Container

To run the Docker container, use the following command:

```bash
podman run -d \
  --name postfix-dkim \
  -p 25:25 \
  -e MAIL_DOMAIN="yourdomain.com" \
  -e MAIL_HOSTNAME="mail.yourdomain.com" \
  -e SASL_USER="user" \
  -e SASL_PASSWORD="password" \
  -e USE_LETSENCRYPT="true" \
  -v $(pwd)/dkim-keys:/etc/opendkim/keys \
  -v /etc/letsencrypt:/etc/letsencrypt \
  postfix-dkim
```

### Persistent Data

To keep the DKIM keys persistent, you should mount a volume to `/etc/opendkim/keys`. The example above uses a local directory `dkim-keys` in the current working directory. You can change this to any other directory.

### Let's Encrypt Integration

If you want to use Let's Encrypt for outgoing TLS, you need to mount your Let's Encrypt directory to `/etc/letsencrypt` in the container and set the `USE_LETSENCRYPT` environment variable to `true`.

The startup script will automatically check if the certificate for `$MAIL_HOSTNAME` is about to expire (less than 30 days) and will try to renew it using `certbot renew`.

### Environment Variables

*   `MAIL_DOMAIN`: The domain for which the mail server will send emails.
*   `MAIL_HOSTNAME`: The hostname of the mail server.
*   `SASL_USER`: The username for SASL authentication.
*   `SASL_PASSWORD`: The password for the SASL user.
*   `SMTP_BIND_ADDRESS`: The IP address that Postfix will use for outgoing mail.
*   `DKIM_SELECTOR`: The DKIM selector to use. Defaults to `default`.
*   `USE_LETSENCRYPT`: Set to `true` to use Let's Encrypt for outgoing TLS. You need to mount your Let's Encrypt directory to `/etc/letsencrypt`.

## User Authentication

You can provide SASL users by mounting a file to `/etc/postfix/sasl_users` containing `username:password` pairs (one per line).

If the file is not present, the script will fall back to using `SASL_USER` and `SASL_PASSWORD` environment variables for a single user.

To manually add users to a running container:

```bash
podman exec -it postfix-dkim /bin/bash
echo "your_password" | saslpasswd2 -p -c -u "yourdomain.com" "your_username"
```

## DKIM Configuration

The startup script will generate a DKIM key for your domain and print the public key to the console. You need to add this public key as a TXT record to your DNS.

To view the public key again, you can run the following command:

```bash
podman logs postfix-dkim
```

The output will contain the DKIM public key in the following format (where `default` is the value of `DKIM_SELECTOR`):

```
default._domainkey IN TXT "v=DKIM1; k=rsa; p=your_public_key"
```
