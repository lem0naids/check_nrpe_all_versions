#!/bin/sh
# Essaie les modes de dialogue NRPE du plus recent au plus ancien et s'arrete
# au premier qui repond. Sert a identifier ce que parle un agent inconnu.
set -u

CHECK=/usr/local/nagios/libexec/check_nrpe
CFG=/etc/check_nrpe.cfg
PORT=5666
CMD=_NRPE_CHECK   # commande interne de NRPE : repond sans config cote agent
TIMEOUT=10

usage() {
    cat >&2 <<USAGE
usage: nrpe-probe [-p port] [-c commande] [-t secondes] <hote>

  -p  port de l'agent a interroger (defaut: 5666)
  -c  commande a demander         (defaut: _NRPE_CHECK)
  -t  delai par tentative         (defaut: 10)
USAGE
    exit 3
}

while getopts 'p:c:t:h' opt; do
    case "$opt" in
        p) PORT=$OPTARG ;;
        c) CMD=$OPTARG ;;
        t) TIMEOUT=$OPTARG ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[ $# -eq 1 ] || usage
HOST=$1

# Un mode "fonctionne" des que le dialogue aboutit, meme si le plugin distant
# renvoie WARNING/CRITICAL : c'est le transport qu'on sonde, pas l'etat du
# service. Seul check_nrpe prefixe ses propres erreurs par "CHECK_NRPE:" ;
# une reponse comme "NRPE: Command 'x' not defined" prouve que la poignee de
# main a reussi, donc que le mode est bon.
try() {
    LABEL="$1"; shift
    OUT=$("$CHECK" -f "$CFG" -H "$HOST" -p "$PORT" -t "$TIMEOUT:CRITICAL" \
                   -c "$CMD" "$@" 2>&1)
    RC=$?
    FIRST=$(echo "$OUT" | head -1)

    # Motifs d'echec de transport. Tout le reste (y compris un WARNING du
    # plugin ou un "NRPE: Command not defined") signifie que le mode marche.
    case "$FIRST" in
        CHECK_NRPE:*|"" \
        |"connect to address"* \
        |*"Connection refused"*|*"Connection reset"*|*"Connection timed out"* \
        |*"handshake"*|*"No route to host"*|*"Name or service not known"*)
            printf '%-28s echec        : %s\n' "$LABEL" "$FIRST"
            return ;;
    esac

    printf '%-28s OK (rc=%s)   : %s\n' "$LABEL" "$RC" "$FIRST"
    printf '\n>>> mode retenu : %s\n' "$LABEL"
    printf '>>> rejouer     : check_nrpe -H %s -p %s -c %s %s\n' \
           "$HOST" "$PORT" "$CMD" "$*"
    exit 0
}

printf 'Sonde de %s:%s (commande: %s)\n\n' "$HOST" "$PORT" "$CMD"
try "v4 + SSL/ADH"
try "v3 + SSL/ADH"        -3
try "v2 + SSL/ADH"        -2
try "v2 + SSL, sans ADH"  -2 -d 0
try "v2 sans SSL"         -2 -n
try "v4 sans SSL"         -n

echo
echo ">>> aucun mode n'a abouti."
exit 2
