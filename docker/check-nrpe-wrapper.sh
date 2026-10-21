#!/bin/sh
# Enrobage de check_nrpe : applique le fichier de reglages par defaut, puis
# transmet TOUS les arguments recus sans aucune alteration.
#
# Les deux regles qui garantissent la transmission exacte :
#   - "$@" (avec les guillemets) preserve le decoupage d'origine : un argument
#     contenant des espaces reste UN argument. $@ ou $* le casseraient.
#   - exec remplace le processus, donc aucun shell intermediaire ne reinterprete
#     quoi que ce soit ensuite.
#
# Les arguments ajoutes le sont AVANT ceux de l'appelant, pour que -a <liste>
# (qui doit rester en dernier) et les surcharges explicites fonctionnent.
set -eu

BIN=/usr/local/nagios/libexec/check_nrpe
CFG=/etc/check_nrpe.cfg

# Si l'appelant fournit deja son propre -f, on n'injecte rien : check_nrpe
# n'accepte qu'un seul fichier de configuration.
for arg in "$@"; do
    case "$arg" in
        -f|--config-file|--config-file=*)
            exec "$BIN" "$@"
            ;;
    esac
done

exec "$BIN" -f "$CFG" "$@"
