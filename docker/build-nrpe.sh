#!/bin/sh
# Compile NRPE avec des parametres Diffie-Hellman de taille choisie (DH_BITS).
set -eu

DH_BITS="${DH_BITS:-2048}"
ENABLE_ARGS="${ENABLE_ARGS:-0}"

# --enable-command-args est ce qui rend dont_blame_nrpe operant. Sans lui le
# demon refuse tout argument client, et la directive reste lettre morte.
ARGS_OPT=""
if [ "$ENABLE_ARGS" = "1" ]; then
    ARGS_OPT="--enable-command-args"
    echo ">>> ATTENTION : arguments clients actives (--enable-command-args)"
fi

./configure \
    --enable-ssl \
    --with-ssl-lib=/usr/lib/x86_64-linux-gnu \
    --with-nrpe-user=nagios \
    --with-nrpe-group=nagios \
    --with-nagios-user=nagios \
    --with-nagios-group=nagios \
    --with-piddir=/run \
    ${ARGS_OPT}

# NRPE code 2048 en dur dans macros/ax_nagios_get_ssl.m4, qui alimente src/Makefile.
sed -i "s/dhparam -C 2048/dhparam -C ${DH_BITS}/" src/Makefile
grep -q "dhparam -C ${DH_BITS}" src/Makefile

# On genere l'en-tete seul d'abord. 'openssl dhparam -C N' nomme sa fonction
# get_dh<N> (get_dh512, get_dh1024...), alors que nrpe.c appelle get_dh2048 :
# sans ce renommage l'edition de liens echoue sur un symbole manquant.
make -C src ../include/dh.h
sed -i "s/get_dh[0-9]\+/get_dh2048/g" include/dh.h
grep -q 'get_dh2048' include/dh.h

echo ">>> parametres DH generes : ${DH_BITS} bits"
grep -c . include/dh.h >/dev/null

# dh.h existe et sa regle n'a pas de prerequis : make ne la regenere pas.
make all
make install-groups-users
make install
make install-config

# Garde-fous : le build echoue si on derive hors de la branche OpenSSL 1.0.
ldd /usr/local/nagios/bin/nrpe            | grep -F libssl.so.1.0
ldd /usr/local/nagios/libexec/check_nrpe  | grep -F libssl.so.1.0
/usr/local/nagios/bin/nrpe --version || true
