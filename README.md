# check_nrpe compatible toutes versions

Conteneur client `check_nrpe` capable d'interroger n'importe quel agent NRPE,
ancien ou recent, plus une cible NRPE locale pour tester.

## Demarrage

    ./init.sh                       # recupere les sources NRPE (4.1.3 + 2.15)
    docker compose up -d --build    # lance SEULEMENT le client

`docker compose up` ne demarre que `nrpe-client`. Les cibles de test locales
(serveurs 4.1.3 et 2.15) sont dans le profil `servers` et ne montent PAS toutes
seules ; il faut les demander explicitement :

    docker compose --profile servers up -d --build   # client + 2 serveurs

    # arret : le profil est requis, sinon les serveurs restent actifs
    docker compose --profile servers down

## Tester en local

Avec le profil `servers` actif : `nrpe-server` (4.1.3), `nrpe-server-v2` (2.15)
et `nrpe-client`. Les deux serveurs sont permissifs par defaut (arguments +
metacaracteres shell) : cibles de test, a ne jamais exposer.

    # 1. la cible repond-elle, et en quel mode ?
    docker compose exec nrpe-client nrpe-probe nrpe-server
    docker compose exec nrpe-client nrpe-probe -p 5666 -t 5 nrpe-server

    # 2. un check complet
    docker compose exec nrpe-client check_nrpe -H nrpe-server -c check_users

    # 3. les commandes disponibles sur la cible : check_users, check_load,
    #    check_root, check_zombie_procs, check_total_procs
    docker compose exec nrpe-client check_nrpe -H nrpe-server -c check_load

    # 4. taille de cle Diffie-Hellman reellement negociee
    docker compose exec nrpe-client \
        openssl s_client -connect nrpe-server:5666 -cipher ADH </dev/null 2>&1 \
        | grep 'Server Temp Key'

    # 5. journal cote serveur (suite negociee, commande executee)
    docker compose exec nrpe-server tail -f /usr/local/nagios/var/nrpe.log

## Interroger un agent reel

    docker compose run --rm nrpe-client nrpe-probe <hote>
    docker compose run --rm nrpe-client nrpe-probe -p 5666 <hote>
    docker compose run --rm nrpe-client check_nrpe -H <hote> -p 5666 -c check_users

Options de la sonde : `-p` port, `-c` commande, `-t` delai par tentative.

## check_nrpe_auto : un check qui marche contre toutes les versions

`check_nrpe` fait UN seul essai dans UN seul mode. `check_nrpe_auto` prend
EXACTEMENT les memes arguments (`-H -c -a -p ...`, transmis a l'identique) mais
essaie les modes du plus recent au plus ancien (v4/v3/v2, avec/sans SSL,
avec/sans ADH) et renvoie le resultat du PREMIER qui se connecte. Une seule
commande, utilisable telle quelle comme check Nagios, quel que soit l'agent :

    docker compose run --rm nrpe-client \
        check_nrpe_auto -H <hote> -c check_ping -a 127.0.0.1

Il s'arrete au premier mode qui repond (rapide sur un agent joignable) ; si
aucun ne se connecte, il rend `CHECK_NRPE_AUTO: aucun mode...` en CRITICAL (2).
`nrpe-probe` reste l'outil pour *voir* quel mode a ete retenu.

Les arguments sont transmis tels quels a `check_nrpe`, y compris ceux contenant
des espaces :

    docker compose run --rm nrpe-client \
        check_nrpe -H <hote> -c show_args -a 'un deux' trois quatre

Il faut nommer `check_nrpe` (ou `nrpe-probe`) apres le service : `docker compose
run` remplace la commande du conteneur par ce qui suit. Passer `-a` avec
plusieurs valeurs fonctionne comme en natif, chaque valeur devenant `$ARG1$`,
`$ARG2$`, etc. Attention : le caractere `!` scinde un argument (separateur du
protocole NRPE) et un argument vide est ignore par le demon.

La cible de test est permissive par defaut : `ENABLE_ARGS=1` (le demon accepte
les arguments), `dont_blame_nrpe=1` et `nasty_metachars=\a` (metacaracteres
shell autorises). C'est voulu pour tester le client ; **ne jamais exposer cette
image**. Pour un demon verrouille, repasser `ENABLE_ARGS` a `0` dans
`docker-compose.yml` et restaurer `nasty_metachars` dans `docker/conf/nrpe.cfg`.
Un agent REEL que tu interroges garde, lui, ses propres reglages.

Depuis l'hote, le port de la cible de test est publie sur 127.0.0.1:5666
(surchargeable : `NRPE_PORT=5667 docker compose up -d`).

## Cible NRPE 2.15 (vieil agent)

Le service `nrpe-server-v2` lance un vrai agent NRPE 2.15 (protocole v2
uniquement, ADH, DH 512 statique), pour tester le client contre un agent
ancien. Publie sur 127.0.0.1:5668 (`NRPE2_PORT=5669 ...` pour surcharger).
Permissif par defaut comme le 4.x : arguments actives (`--enable-command-args`
+ `dont_blame_nrpe=1`) et filtre nasty desactive (`NASTY_METACHARS` vide,
patche a la compilation car c'est une constante en 2.x).

    docker compose exec nrpe-client check_nrpe_auto -H nrpe-server-v2 -c check_users
    docker compose exec nrpe-client nrpe-probe nrpe-server-v2

Notes de build (compat code 2013 / OpenSSL 2016, voir docker/README.md) :
aucune lib OpenSSL modifiee ; un header `dh.h` renomme pour une collision de
garde, socat pour le mode inetd, et execution sous l'utilisateur nagios.

## Arret

    docker compose down          # -v pour supprimer aussi le reseau

## Details techniques

Voir docker/README.md : choix d'OpenSSL 1.0.2, plancher Diffie-Hellman
d'OpenSSL 3.x, et syntaxe piegeuse de /etc/check_nrpe.cfg.
