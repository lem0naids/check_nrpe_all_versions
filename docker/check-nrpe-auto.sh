#!/bin/sh
# check_nrpe "tolerant" : memes arguments que check_nrpe (-H -c -a -p ...),
# transmis a l'IDENTIQUE, mais on essaie tous les modes de dialogue NRPE du
# plus recent au plus ancien et on renvoie le resultat du PREMIER qui se
# connecte. Une seule commande qui marche contre n'importe quelle version.
#
#   check_nrpe_auto -H agent.example.net -c check_ping -a 127.0.0.1
#
# Les arguments de l'appelant sont conserves dans "$@" et places APRES les
# drapeaux de mode, donc un -a <liste> en fin de ligne reste bien en derniere
# position (contrainte de check_nrpe). "$@" preserve le decoupage exact.
set -u

BIN=/usr/local/nagios/libexec/check_nrpe
CFG=/etc/check_nrpe.cfg

# Injecte le fichier de reglages par defaut, sauf si l'appelant a deja -f.
set -- "$@"
INJECT_CFG=1
for a in "$@"; do
    case "$a" in
        -f|--config-file|--config-file=*) INJECT_CFG=0 ;;
    esac
done

# Modes essayes, du plus recent au plus ancien. Un par ligne : flags de mode.
# (une ligne vide = aucun flag = v4 + SSL/ADH, le defaut)
# "NONE" = aucun flag (v4 + SSL/ADH). On ne peut pas utiliser une ligne vide :
# le saut de ligne etant un separateur IFS, une ligne vide en tete serait avalee et le
# mode v4 jamais essaye.
MODES='NONE
-3
-2
-2 -d 0
-2 -n
-n'

LABELS='v4+SSL/ADH
v3+SSL/ADH
v2+SSL/ADH
v2+SSL sans ADH
v2 sans SSL
v4 sans SSL'

is_transport_error() {
    case "$1" in
        CHECK_NRPE:*|CHECK_NRPE\ STATE*|"" \
        |"connect to address"*|*"Connection refused"*|*"Connection reset"* \
        |*"Connection timed out"*|*"Socket timeout"*|*"timeout after"* \
        |*"handshake"*|*"No route to host"* \
        |*"Name or service not known"*|*"Could not resolve"*) return 0 ;;
    esac
    return 1
}

LAST=""
i=0
# Parcours des modes dans le shell principal (pas de sous-shell) pour pouvoir
# sortir avec le code du plugin des qu'un mode se connecte.
OLDIFS=$IFS
IFS='
'
for FLAGS in $MODES; do
    IFS=$OLDIFS
    i=$((i + 1))
    [ "$FLAGS" = "NONE" ] && FLAGS=""
    if [ "$INJECT_CFG" -eq 1 ]; then
        # shellcheck disable=SC2086
        OUT=$("$BIN" -f "$CFG" $FLAGS "$@" 2>&1); RC=$?
    else
        # shellcheck disable=SC2086
        OUT=$("$BIN" $FLAGS "$@" 2>&1); RC=$?
    fi
    FIRST=$(printf '%s\n' "$OUT" | head -1)
    if is_transport_error "$FIRST"; then
        LAST="$FIRST"
        IFS='
'
        continue
    fi
    # Succes de transport : on rend le resultat complet et le code du plugin.
    printf '%s\n' "$OUT"
    exit "$RC"
done
IFS=$OLDIFS

echo "CHECK_NRPE_AUTO: aucun mode n'a pu se connecter (dernier: ${LAST:-N/A})"
exit 2
