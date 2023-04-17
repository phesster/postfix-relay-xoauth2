FROM ubuntu:22.04
ENV DEBCONF_NOWARNINGS=yes
ENV DEBIAN_FRONTEND=noninteractive
#ENV DEBIAN_PRIORITY=critical
MAINTAINER Patrick Hess phesster@gmail.com

#
# Adaptation of https://hub.docker.com/r/mwader/postfix-relay/ and
#    https://github.com/tarickb/sasl-xoauth2
#

###
### KeyID noted at https://launchpad.net/~sasl-xoauth2/+archive/ubuntu/stable
###

RUN \
  echo "APT::Install-Suggests 0;\nAPT::Install-Recommends 0;" | tee /etc/apt/apt.conf.d/00-no-install-recommends && \
  echo "path-exclude=/usr/share/locale/*\npath-exclude=/usr/share/man/*\npath-exclude=/usr/share/doc/*\n" | tee  /etc/dpkg/dpkg.cfg.d/01-nodoc && \
  apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y software-properties-common apt-transport-https && \
  apt-get -y --no-install-recommends install \
    procps \
    postfix \
    libsasl2-modules \
    opendkim \
    opendkim-tools \
    ca-certificates \
    gpg \
    gpg-agent \
    dirmngr \
    libcurl4 \
    libjsoncpp25 \
    sasl2-bin \
    libgcc-s1 \
    tzdata \
    rsyslog && \
  echo "deb https://ppa.launchpadcontent.net/sasl-xoauth2/stable/ubuntu/ jammy main" | tee /etc/apt/sources.list.d/sasl-xoauth2-ubuntu-stable-jammy.list && \
  gpg --recv-keys --keyserver keyserver.ubuntu.com 2E733F026005F791 && \
  gpg --export 2E733F026005F791 > /etc/apt/trusted.gpg.d/sasl-xoauth2-ubuntu-stable.gpg && \
  apt-get update && \
  apt-get -y --no-install-recommends install \
    sasl-xoauth2 && \
  apt-get -y clean && \
  apt-get -y autoremove && \
  rm -rf /var/lib/apt/lists/* /etc/rsyslog.conf && \
  update-ca-certificates && \
  mkdir -p /var/spool/postfix/etc/ssl/certs && \
  cp -p /etc/ssl/certs/ca-certificates.crt /var/spool/postfix/etc/ssl/certs/ && \
  mkdir -p /etc/opendkim/keys && \
  sed -i ' s,-name,\\( -name, ' /usr/lib/postfix/configure-instance.sh && \
  sed -i ' s,-not,-o -name \\\*.crt \\) -not, ' /usr/lib/postfix/configure-instance.sh

COPY etc/sasl-xoauth2.conf /etc/sasl-xoauth2.conf
COPY etc/tokens/sender.tokens.json /var/spool/postfix/etc/tokens/sender.tokens.json
COPY etc/postfix/sasl_passwd /etc/postfix/sasl_passwd
COPY run /root/

RUN \
  chown postfix:postfix /var/spool/postfix/etc/tokens/sender.tokens.json


# Default config:
# Open relay, trust docker links for firewalling.
# Try to use TLS when sending to other smtp servers.
# No TLS for connecting clients, trust docker network to be safe
ENV \
  POSTFIX_myhostname=hostname \
  POSTFIX_mydestination=localhost \
  POSTFIX_mynetworks=0.0.0.0/0 \
  POSTFIX_smtp_tls_security_level=may \
  POSTFIX_smtpd_tls_security_level=none \
  OPENDKIM_Socket=inet:12301@localhost \
  OPENDKIM_Mode=sv \
  OPENDKIM_UMask=002 \
  OPENDKIM_Syslog=yes \
  OPENDKIM_InternalHosts="0.0.0.0/0, ::/0" \
  OPENDKIM_KeyTable=refile:/etc/opendkim/KeyTable \
  OPENDKIM_SigningTable=refile:/etc/opendkim/SigningTable \
  RSYSLOG_TIMESTAMP=no \
  RSYSLOG_LOG_TO_FILE=no

VOLUME ["/var/lib/postfix", "/var/mail", "/var/spool/postfix", "/etc/opendkim/keys"]
EXPOSE 25
CMD ["/root/run"]
