#!/bin/sh
# Recupere les sources NRPE attendues par les Dockerfile.
# Les versions sont figees : un changement amont peut casser le build
# (le patch DH 4.x depend de la forme du Makefile genere, celui de la 2.15
# depend de l'include dh.h).
set -eu

NRPE_REPO=https://github.com/NagiosEnterprises/nrpe.git
NRPE_COMMIT=8db61f6ed06e112d09d136c3887ef06a16200af6   # 4.1.3
NRPE2_TAG=nrpe-2-15                                     # dernier 2.x

# --- Sources 4.1.3 (clone complet, checkout du commit fige) ---
if [ -d nrpe/.git ]; then
    echo "nrpe/ existe deja, rien a faire."
else
    git clone "$NRPE_REPO" nrpe
fi
git -C nrpe checkout --quiet "$NRPE_COMMIT"

# --- Sources 2.15 (archive du tag, arborescence propre sans .git) ---
if [ -d nrpe215 ] && [ -f nrpe215/include/common.h ]; then
    echo "nrpe215/ existe deja, rien a faire."
else
    rm -rf nrpe215
    mkdir nrpe215
    git -C nrpe archive "$NRPE2_TAG" | tar -x -C nrpe215
fi

echo "Sources NRPE 4.1.3 sur $(git -C nrpe describe --always)"
echo "Sources NRPE 2.15 depuis le tag $NRPE2_TAG"
echo "Lancer : docker compose up -d --build"
