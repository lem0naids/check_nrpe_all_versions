# check_nrpe – compatible toutes versions

Un client **`check_nrpe` universel**, packagé en conteneur, capable d'interroger
n'importe quel agent NRPE (de la vieille branche 2.x jusqu'aux 4.x récentes),
là où un `check_nrpe` moderne échoue sur les agents anciens (ADH, DH 512,
paquets v2…).

Le dépôt fournit aussi :

- **`check_nrpe_auto`** — un check qui essaie tout seul tous les modes et marche
  quelle que soit la version de l'agent ;
- **`nrpe-probe`** — une sonde qui identifie le mode parlé par un agent inconnu ;
- **deux cibles de test** locales (NRPE 4.1.3 et 2.15) pour s'exercer.

Base technique : Ubuntu 16.04 / OpenSSL 1.0.2 (standard, non modifié), seule
branche qui dialogue nativement en ADH + DH 512 avec les vieux agents. Détails
dans [docker/README.md](docker/README.md).

---

## Prérequis

- Docker avec le plugin Compose v2 (`docker compose …`)
- `git`
- Un accès réseau au premier lancement (clonage des sources NRPE)

---

## Installation

```sh
git clone https://github.com/lem0naids/check_nrpe_all_versions.git
cd check_nrpe_all_versions

./init.sh                      # recupere les sources NRPE amont (4.1.3 + 2.15)
docker compose up -d --build   # construit l'image et lance le client
```

`init.sh` récupère les sources figées (commit 4.1.3 + tag `nrpe-2-15`) ; elles
ne sont pas versionnées dans le dépôt, uniquement reconstruites ici.

`docker compose up` ne démarre **que le client** (`nrpe-client`). Les cibles de
test ne montent pas automatiquement — voir
[Lancer les serveurs de test](#lancer-les-serveurs-de-test-unsafe).

---

## Usage

Le client est un conteneur qui reste actif ; on lui fait exécuter des commandes
avec `docker compose exec nrpe-client …`.

### `check_nrpe_auto` — recommandé

Mêmes arguments que `check_nrpe` (`-H`, `-c`, `-a`, `-p`…), transmis à
l'identique, mais il essaie tous les modes du plus récent au plus ancien
(v4 → v3 → v2, avec/sans SSL, avec/sans ADH) et renvoie le résultat du **premier
qui se connecte**. Une seule commande, utilisable directement comme check
Nagios, quel que soit l'agent :

```sh
docker compose exec nrpe-client \
    check_nrpe_auto -H <hote> -c check_ping -a 127.0.0.1
```

- s'arrête au premier mode qui répond (rapide sur un agent joignable) ;
- si aucun ne se connecte → `CHECK_NRPE_AUTO: aucun mode…` en CRITICAL (code 2).

### `check_nrpe` — le client brut

Un seul essai, dans un seul mode (v4 par défaut). Utile quand tu sais déjà ce
que parle l'agent :

```sh
docker compose exec nrpe-client check_nrpe -H <hote> -c check_users
docker compose exec nrpe-client check_nrpe -H <hote> -2 -c check_users   # force v2
```

### `nrpe-probe` — identifier le mode d'un agent

Teste les modes dans l'ordre et s'arrête au premier qui marche, en affichant
la ligne `check_nrpe` à rejouer :

```sh
docker compose exec nrpe-client nrpe-probe <hote>
docker compose exec nrpe-client nrpe-probe -p 5666 -t 5 <hote>
```

Options : `-p` port · `-c` commande · `-t` délai par tentative.

### Passer des arguments (`-a`)

Les arguments sont transmis tels quels, y compris ceux contenant des espaces :

```sh
docker compose exec nrpe-client \
    check_nrpe_auto -H <hote> -c check_ping -a 127.0.0.1
```

Chaque valeur après `-a` devient `$ARG1$`, `$ARG2$`, etc. Deux limites, qui
viennent du protocole NRPE (pas du conteneur) :

- le caractère `!` **scinde** un argument (c'est le séparateur du protocole) ;
- un argument **vide** est ignoré par le démon.

Côté agent, le passage d'arguments doit être autorisé (compilé avec
`--enable-command-args` + `dont_blame_nrpe=1`). Les deux cibles de test de ce
dépôt le sont.

### Interroger un agent distant (sans les cibles de test)

Le client sert aussi tel quel contre de vrais agents :

```sh
docker compose run --rm nrpe-client check_nrpe_auto -H agent.example.net -c check_load
docker compose run --rm nrpe-client nrpe-probe        -H agent.example.net
```

---

## Lancer les serveurs de test (UNSAFE)

> ⚠️ **Les deux cibles de test sont volontairement non sécurisées.** Elles
> acceptent les arguments client **et** les métacaractères shell, sur une base
> Ubuntu 16.04 EOL sans correctifs. C'est fait pour exercer le client — **ne
> jamais les exposer sur un réseau.** Les ports ne sont publiés que sur
> `127.0.0.1`.

Elles sont isolées dans le profil Compose `servers` et ne démarrent donc
**jamais** avec un simple `docker compose up`. Il faut les demander :

```sh
docker compose --profile servers up -d --build     # client + 2 serveurs
```

| Service          | Version | Port hôte (127.0.0.1) | Particularités                    |
|------------------|---------|-----------------------|-----------------------------------|
| `nrpe-server`    | 4.1.3   | 5666 (`NRPE_PORT`)    | v2/v3/v4, ADH, DH 512             |
| `nrpe-server-v2` | 2.15    | 5668 (`NRPE2_PORT`)   | v2 uniquement, ADH, DH 512 statique |

Les deux sont permissifs par défaut (arguments + métacaractères). Pour un démon
verrouillé : `ENABLE_ARGS=0` dans `docker-compose.yml` et restaurer
`nasty_metachars` dans `docker/conf/nrpe.cfg` (voir [docker/README.md](docker/README.md)).

### Exemples contre les cibles

```sh
# quel mode parle la cible ?
docker compose exec nrpe-client nrpe-probe nrpe-server
docker compose exec nrpe-client nrpe-probe nrpe-server-v2

# checks
docker compose exec nrpe-client check_nrpe_auto -H nrpe-server    -c check_users
docker compose exec nrpe-client check_nrpe_auto -H nrpe-server-v2 -c check_ping -a 127.0.0.1

# commandes dispo : check_users, check_load, check_root,
#                   check_zombie_procs, check_total_procs, check_ping

# taille de clé Diffie-Hellman réellement négociée
docker compose exec nrpe-client \
    openssl s_client -connect nrpe-server:5666 -cipher ADH </dev/null 2>&1 \
    | grep 'Server Temp Key'

# journal côté serveur (suite négociée, commande exécutée)
docker compose exec nrpe-server tail -f /usr/local/nagios/var/nrpe.log
```

### Arrêt

```sh
docker compose --profile servers down     # requis pour stopper AUSSI les serveurs
docker compose down                        # ne stoppe que le client
```

> Sans `--profile servers`, `docker compose down` laisse les serveurs tourner.

---

## Détails techniques

Choix d'OpenSSL 1.0.2, plancher Diffie-Hellman d'OpenSSL 3.x, syntaxe du fichier
`check_nrpe.cfg`, patchs de compilation 2.15 (collision de header `dh.h`, socat
pour le mode inetd, exécution sous l'utilisateur `nagios`) : voir
[docker/README.md](docker/README.md).
