# Overview

This is an incorporation of [tarickb's SASL-OAuth2](https://github.com/tarickb/sasl-xoauth2/)
into [mwader's Postfix-Relay](https://hub.docker.com/r/mwader/postfix-relay/)
on top of a [Ubuntu](https://hub.docker.com/_/ubuntu) "Jammy" 22.04 base image.
For detailed information on any of these, please read their specific 
documentation.

## postfix-relay

Postfix SMTP relay docker image. Useful for sending email without using an
external SMTP server.

Default configuration is an open relay that relies on docker networking for
protection. Be careful to not expose it publicly.


### Postfix variables (postfix-relay)

Postfix [configuration options](http://www.postfix.org/postconf.5.html) can be set
using `POSTFIX_<name>` environment variables. See [Dockerfile](Dockerfile) for default
configuration. You probably want to set `POSTFIX_myhostname` (the FQDN used by 220/HELO).

Note that `POSTFIX_myhostname` will change the postfix option
[myhostname](http://www.postfix.org/postconf.5.html#myhostname).

You can modify master.cf using postconf with `POSTFIXMASTER_` variables. All double `__` symbols will be replaced with `/`. For example

### Postfix master.cf variables

```
environment:
- POSTFIXMASTER_submission__inet=submission inet n - y - - smtpd -o syslog_name=postfix/submission
```
will emit the following into the container and run that command

```
postconf -Me submission/inet="submission inet n - y - - smtpd -o syslog_name=postfix/submission"
```

### Postfix lookup tables

You can also create multiline [tables](http://www.postfix.org/DATABASE_README.html#types) using `POSTMAP_<filename>` like this example:
```
environment:
  - POSTFIX_transport_maps=hash:/etc/postfix/transport
  - |
    POSTMAP_transport=gmail.com smtp
    mydomain.com relay:[relay1.mydomain.com]:587
    * relay:[relay2.mydomain.com]:587
```
which will generate the file `/etc/postfix/transport` in the container
```
gmail.com smtp
mydomain.com relay:[relay1.mydomain.com]:587
* relay:[relay2.mydomain.com]:587
```
and run the command `postmap /etc/postfix/transport`.

### Example Gratis:

This is a snippet of how I initialize the container:
```
environment:
  - POSTFIXMASTER_submission__inet="submission inet n - y - - smtpd -o syslog_name=postfix/submission"
  - POSTFIX_smtpd_tls_security_level="may"
  - POSTFIX_smtpd_reject_unlisted_recipient="no"
  - POSTFIX_myhostname="POSTFIX"
  - POSTFIX_smtpd_relay_restrictions="permit_mynetworks, permit_sasl_authenticated, check_relay_domains"
  - POSTFIX_smtp_use_tls="yes"
  - POSTFIX_smtp_sasl_auth_enable="yes"
  - POSTFIX_smtp_sasl_security_options="noanonymous"
  - POSTFIX_smtp_sasl_mechanism_filter="xoauth2"
  - POSTFIX_smtp_tls_security_level="encrypt"
  - POSTFIX_smtp_tls_CAfile="/etc/ssl/certs/ca-certificates.crt"
  - POSTFIX_transport_maps="hash:/etc/postfix/transport"
  - POSTMAP_transport="*       relay:[smtp.gmail.com]:587"
  - POSTFIX_smtp_sasl_password_maps="hash:/etc/postfix/sasl_passwd"
  - |
    POSTMAP_sasl_passwd=
    [smtp.gmail.com]:587   user@gmail.com:/etc/tokens/sender.tokens.json
```

Then, I initialize the SASL-XOAuth2 configuration files in the container
from known-working existing files with these commands.  (This is just
my hackneyed way to do it, you may have a better way)
```
  docker cp sasl-xoauth2.conf postfix-relay-container:/tmp
  docker exec -it --workdir /root --user root postfix-relay-container bash -c "cat /tmp/sasl-xoauth2.conf > /etc/sasl-xoauth2.conf"
  docker exec -it --workdir /root --user root postfix-relay-container bash -c "mkdir  /etc/tokens  /var/spool/postfix/etc/tokens"
  docker cp sender.tokens.json postfix-relay-container:/etc/tokens/sender.tokens.json
  docker exec -it --workdir /root --user root postfix-relay-container bash -c "chown postfix:postfix /etc/tokens/sender.tokens.json"
  docker exec -it --workdir /root --user root postfix-relay-container bash -c "cp -p /etc/tokens/sender.tokens.json /var/spool/postfix/etc/tokens/sender.tokens.json"
  docker exec -it --workdir /root --user root postfix-relay-container bash -c "rm -f /tmp/sasl-xoauth2.conf /tmp/sender.tokens.json"
```

#### Hint for how to create the tokens

This is how I generated the tokens on another host (Your Mileage May Vary).
This is only a _HINT_!  Please read the documetation (enumerated above).
```
sasl-xoauth2-token-tool.py get-token --client-id="55XXXXXXXXXX-pXXXXXkqXXXXXXXXXXXXXXXXXXXXXXX.apps.googleusercontent.com" --client-secret="GOCSPX-XXXXXXXXXXXXXXXXXXXXXXXXXXXX" --scope="https://mail.google.com/" gmail tokens-stored-in-this-file
```

### OpenDKIM variables

OpenDKIM [configuration options](http://opendkim.org/opendkim.conf.5.html) can be set
using `OPENDKIM_<name>` environment variables. See [Dockerfile](Dockerfile) for default
configuration. For example `OPENDKIM_Canonicalization=relaxed/simple`.

### Using docker run
```
docker run -e POSTFIX_myhostname=smtp.domain.tld phesster/postfix-relay-xoauth2
```

### Using docker-compose
```
app:
  # use hostname "smtp" as SMTP server

smtp:
  image: phesster/postfix-relay-xoauth2
  restart: always
  environment:
    - POSTFIX_myhostname=smtp.domain.tld
    - OPENDKIM_DOMAINS=smtp.domain.tld
```

### Logging
By default container only logs to stdout. If you also wish to log `mail.*` messages to file on persistent volume, you can do something like:

```
environment:
  ...
  - RSYSLOG_LOG_TO_FILE=yes
  - RSYSLOG_TIMESTAMP=yes
volumes:
  - /your_local_path:/var/log/
```

You can also forward log output to remote syslog server if you define `RSYSLOG_REMOTE_HOST` variable. It always uses UDP protocol and port `514` as default value,
port number can be changed to different one with `RSYSLOG_REMOTE_PORT`. Default format of forwarded messages is defined by Rsyslog template `RSYSLOG_ForwardFormat`,
you can change it to [another template](https://www.rsyslog.com/doc/v8-stable/configuration/templates.html) (section Reserved Template Names) if you wish with `RSYSLOG_REMOTE_TEMPLATE` variable.

```
environment:
  ...
  - RSYSLOG_REMOTE_HOST=my.remote-syslog-server.com
  - RSYSLOG_REMOTE_PORT=514
  - RSYSLOG_REMOTE_TEMPLATE=RSYSLOG_ForwardFormat
```

#### Advanced logging configuration

If configuration via environment variables is not flexible enough it's possible to configure rsyslog directly: `.conf` files in the `/etc/rsyslog.d` directory will be [sorted alphabetically](https://www.rsyslog.com/doc/v8-stable/rainerscript/include.html#file) and included into the primary configuration.

### Timezone
Wrong timestamps in log can be fixed by setting proper timezone.
This parameter is handled by Debian base image.

```
environment:
  ...
  - TZ=Europe/Prague
```

### Known issues

#### I see `key data is not secure: /etc/opendkim/keys can be read or written by other users` error messages.

Some Docker distributions like Docker for Windows and RancherOS seems to handle
volume permission in way that does not work with OpenDKIM default behavior of
ensuring safe permissions on private keys.

A workaround is to disable the check using a `OPENDKIM_RequireSafeKeys=no` environment variable.

## SPF
When sending email using your own SMTP server it is probably a good idea
to setup [SPF](https://en.wikipedia.org/wiki/Sender_Policy_Framework) for the
domain you're sending from.

## DKIM
To enable [DKIM](https://en.wikipedia.org/wiki/DomainKeys_Identified_Mail),
specify a whitespace-separated list of domains in the environment variable
`OPENDKIM_DOMAINS`. The default DKIM selector is "mail", but can be changed to
"`<selector>`" using the syntax `OPENDKIM_DOMAINS=<domain>=<selector>`.

At container start, RSA key pairs will be generated for each domain unless the
file `/etc/opendkim/keys/<domain>/<selector>.private` exists. If you want the
keys to persist indefinitely, make sure to mount a volume for
`/etc/opendkim/keys`, otherwise they will be destroyed when the container is
removed.

DNS records to configure can be found in the container log or by running `docker exec <container> sh -c 'cat /etc/opendkim/keys/*/*.txt` you should see something like this:
```bash
$ docker exec 7996454b5fca sh -c 'cat /etc/opendkim/keys/*/*.txt'

mail._domainkey.smtp.domain.tld. IN	TXT	( "v=DKIM1; h=sha256; k=rsa; "
	  "p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0Dx7wLGPFVaxVQ4TGym/eF89aQ8oMxS9v5BCc26Hij91t2Ci8Fl12DHNVqZoIPGm+9tTIoDVDFEFrlPhMOZl8i4jU9pcFjjaIISaV2+qTa8uV1j3MyByogG8pu4o5Ill7zaySYFsYB++cHJ9pjbFSC42dddCYMfuVgrBsLNrvEi3dLDMjJF5l92Uu8YeswFe26PuHX3Avr261n"
	  "j5joTnYwat4387VEUyGUnZ0aZxCERi+ndXv2/wMJ0tizq+a9+EgqIb+7lkUc2XciQPNuTujM25GhrQBEKznvHyPA6fHsFheymOuB763QpkmnQQLCxyLygAY9mE/5RY+5Q6J9oDOQIDAQAB" )  ; ----- DKIM key mail for smtp.domain.tld
```

## License
postfix-relay-xoauth2 is licensed under the MIT license. See [LICENSE](LICENSE) for the
full license text.
