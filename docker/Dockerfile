# Ubuntu 16.04 (xenial) = OpenSSL 1.0.2g : derniere Ubuntu de la branche 1.0.
# 18.04 et au-dela sont en 1.1.1+, qui casse la negociation ADH par defaut de NRPE.
FROM ubuntu:16.04

# xenial est EOL mais archive.ubuntu.com sert toujours ses index.
# Si un jour il bascule vers old-releases.ubuntu.com, decommente le sed ci-dessous.
# RUN sed -i 's|http://archive.ubuntu.com/ubuntu|http://old-releases.ubuntu.com/ubuntu|g' /etc/apt/sources.list
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
        build-essential autoconf automake libssl-dev libwrap0-dev openssl \
        nagios-plugins-basic nagios-plugins-standard \
        procps net-tools \
 && rm -rf /var/lib/apt/lists/*

# Trace de la version reellement liee, visible dans le log de build.
RUN openssl version -a | head -2

RUN groupadd -r nagios && useradd -r -g nagios -d /usr/local/nagios -s /bin/false nagios

# Taille des parametres Diffie-Hellman generes a la compilation.
# NRPE code 2048 en dur dans macros/ax_nagios_get_ssl.m4 ; on patche le Makefile
# genere par configure. 512 n'a d'interet que pour tester d'anciens agents.
ARG DH_BITS=2048

# 1 = le demon accepte les arguments du client ($ARG1$). Risque de securite,
# necessaire seulement pour tester ce chemin. Voir docker/README.md.
ARG ENABLE_ARGS=0

COPY nrpe /usr/src/nrpe
WORKDIR /usr/src/nrpe

COPY docker/build-nrpe.sh /usr/local/bin/build-nrpe.sh
RUN DH_BITS="${DH_BITS}" ENABLE_ARGS="${ENABLE_ARGS}" /usr/local/bin/build-nrpe.sh

# NRPE abandonne ses privileges vers nagios : il lui faut un repertoire de log
# qui lui appartient (il ne peut pas ecrire sur /dev/stdout, qui est a root).
RUN install -d -o nagios -g nagios -m 755 /usr/local/nagios/var

# Reglages client par defaut + sonde multi-versions.
COPY docker/check-nrpe.cfg        /etc/check_nrpe.cfg
COPY docker/nrpe-probe.sh         /usr/local/bin/nrpe-probe
COPY docker/check-nrpe-wrapper.sh /usr/local/bin/check_nrpe
COPY docker/check-nrpe-auto.sh    /usr/local/bin/check_nrpe_auto
RUN chmod +x /usr/local/bin/nrpe-probe /usr/local/bin/check_nrpe \
             /usr/local/bin/check_nrpe_auto

EXPOSE 5666
CMD ["/usr/local/nagios/bin/nrpe", "-c", "/usr/local/nagios/etc/nrpe.cfg", "-f"]
