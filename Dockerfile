FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get dist-upgrade -y \
    && apt-get install -y wget gnupg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/trusted.gpg.d/psyphi.gpg] https://psyphi.net/apt noble-stable main" > /etc/apt/sources.list.d/psyphi.list \
    && wget -O- http://psyphi.net/apt/repo@psyphi.net.key | gpg --dearmor -o  /etc/apt/trusted.gpg.d/psyphi.gpg \
    && apt-get update \
    && apt-get install -y build-essential make libmodule-build-perl libclass-accessor-perl libconfig-inifiles-perl libdbi-perl libtemplate-perl liblingua-en-inflect-perl libio-capture-perl libio-stringy-perl libreadonly-perl libxml-simple-perl libhtml-parser-perl libhttp-server-simple-perl libyaml-tiny-perl libcrypt-cbc-perl libcrypt-blowfish-perl liblocale-maketext-lexicon-perl libhttp-clientdetect-perl liblingua-en-pluraltosingular-perl libmime-base64-perl libyaml-tiny-perl liblocale-maketext-lexicon-perl libdata-uuid-perl libcrypt-mysql-perl libdbd-sqlite3-perl libdbd-mysql-perl libdigest-md5-perl libdigest-sha-perl libnet-ldap-perl libtest-perl-critic-perl  libtest-pod-coverage-perl  libtest-pod-perl libtest-kwalitee-perl libmodule-build-perl libtest-trap-perl libxml-treebuilder-perl libxml-xpath-perl libtest-number-delta-perl libtest-distribution-perl
