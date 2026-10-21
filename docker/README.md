# check_nrpe « compatible toutes versions »

Image client unique, destinee a interroger n'importe quel agent NRPE,
du plus ancien au plus recent.

## Pourquoi OpenSSL 1.0.2 (Ubuntu 16.04)

Le choix de la base est dicte par le client, pas par le serveur. Mesures faites
dans ces conteneurs :

| Client            | ADH | DH 512 | DH 768 | DH 1024 |
|-------------------|-----|--------|--------|---------|
| OpenSSL 1.0.2g    | oui, sans reglage | oui | oui | oui |
| OpenSSL 3.0.2     | seulement avec `@SECLEVEL=0` | non | non | oui |

OpenSSL 3.x refuse tout parametre Diffie-Hellman sous 1024 bits avec
« dh key too small ». Ce plancher est un controle interne : **aucune directive
d'`openssl.cnf` ne le leve**, `@SECLEVEL=0` n'y change rien (il ne fait que
reautoriser les suites anonymes). Un client OpenSSL 3.x est donc strictement
moins compatible qu'un 1.0.2 : c'est pour cela qu'il n'y en a pas ici.

A l'inverse, `@SECLEVEL` n'existe pas avant OpenSSL 1.1.0 : sur cette image le
jeton est rejete (`invalid command`) et casserait la connexion. Il ne faut donc
pas l'ajouter, ni dans la liste de suites, ni ailleurs.

## Le fichier /etc/check_nrpe.cfg

`check_nrpe -f` ne lit PAS un fichier cle=valeur. Le contenu est decoupe sur les
espaces et passe tel quel a `getopt` comme une ligne de commande. Donc :

- chaque ligne doit etre une option longue complete : `--cipher-list=...`
- **sans** le `--`, l'option est silencieusement ignoree (aucune erreur)
- **aucun commentaire** : le premier mot non-option arrete l'analyse et annule
  tout le reste du fichier, toujours sans erreur

Verification que le fichier est bien pris en compte : y mettre une suite
inexistante doit faire echouer l'appel.

    check_nrpe -f /etc/check_nrpe.cfg -H <hote> -c _NRPE_CHECK   # rc=0
    # avec --cipher-list=CIPHER_INEXISTANT                        -> rc=2

## Transmission des arguments

`/usr/local/bin/check_nrpe` est un enrobage qui injecte `-f /etc/check_nrpe.cfg`
puis transmet l'argv recu **sans aucune alteration** (`exec "$BIN" ... "$@"`).
Si l'appelant passe deja son propre `-f` / `--config-file`, rien n'est injecte.

Verifie en montant un mouchard d'argv a la place du binaire : argument vide
conserve, espaces groupes, `$ * ' \` intacts, options inconnues transmises.

    check_nrpe -H h -c 'ma commande' -a 'un deux' trois '' 'a$b*c'
    -> argv: <-f> </etc/check_nrpe.cfg> <-H> <h> <-c> <ma commande>
             <-a> <un deux> <trois> <> <a$b*c>

Deux limites qui viennent de NRPE, pas de l'enrobage :

- le protocole separe les arguments par `!` : un argument contenant `!` est
  scinde, et les guillemets n'y changent rien (`-a "a!b"` -> deux arguments) ;
- un argument vide est ignore par le demon (`-a "" x` -> `$ARG1$` vaut `x`).

Cote compose, le service client utilise `command:` et non `entrypoint:` : c'est
ce qui permet a `docker compose run` de remplacer la commande et de transmettre
les arguments. Avec un `entrypoint`, ils partiraient dans `sleep`.

## Usage

    docker compose run --rm nrpe-client check_nrpe -H <hote> -c check_users
    docker compose run --rm nrpe-client nrpe-probe <hote>

`nrpe-probe [-p port] [-c commande] [-t secondes] <hote>` essaie les modes du
plus recent au plus ancien (v4/v3/v2, avec et sans SSL, avec et sans ADH) et
s'arrete au premier qui repond, en affichant la ligne check_nrpe a rejouer.

## Metacaracteres "nasty" cote serveur

Le demon rejette toute requete (nom de commande ET arguments) contenant un
caractere de `nasty_metachars`. Defaut compile :  `` |`&><'\[]{};\r\n `` ; une
requete fautive est refusee avec `Request contained illegal metachars!` avant
meme la recherche de la commande.

La cible de test desactive ce filtre (`docker/conf/nrpe.cfg`) pour laisser
passer les metacaracteres shell. Deux pieges rencontres :

- **on ne peut pas vider la directive** : `nasty_metachars=` fait quitter le
  demon en erreur. Le parseur lit la valeur avec `strtok(NULL, "\n")`, qui
  renvoie NULL quand il n'y a rien apres le `=`, et traite ca comme
  "No variable value specified" (sortie en erreur) ;
- **le filtre tourne toujours** : non definie, la directive retombe sur la
  liste compilee. On ne peut donc pas "l'enlever".

Contournement retenu : `nasty_metachars=\a` — un seul caractere de controle
(sonnette) qui n'apparait jamais dans une requete texte. Seul `\a` reste
bloque ; `; | & > <` etc. passent.

Verifie : avec le defaut, `-c 'foo>bar'` -> `illegal metachars` (connexion
coupee) ; avec `\a`, la meme requete atteint la recherche de commande
(`Command 'foo>bar' not defined`).

Hors lab, laisser le filtre par defaut : il protege contre l'injection de
commandes via les arguments.

## Le service nrpe-server

Ce n'est qu'une cible de test locale, pas un deploiement. Volontairement
permissif, pour exercer tous les chemins du client :

- `DH_BITS=512` (surchargeable) : simule un vieil agent a cle faible ;
- `ENABLE_ARGS=1` au build + `dont_blame_nrpe=1` : accepte les arguments ;
- `nasty_metachars=\a` : laisse passer les metacaracteres shell.

Base EOL sans correctifs, et ces trois reglages en font une cible qu'un
attaquant retournerait facilement : **a garder sur 127.0.0.1, jamais exposee**.
Pour un demon realiste, repasser `ENABLE_ARGS=0` dans `docker-compose.yml`,
remettre `dont_blame_nrpe=0` et le `nasty_metachars` par defaut dans
`docker/conf/nrpe.cfg`.

Les deux serveurs sont dans le profil Compose `servers` : ils ne demarrent
qu'avec `docker compose --profile servers up -d`, jamais avec un simple
`docker compose up` (qui ne lance que le client). Idem a l'arret : `docker
compose down` sans `--profile servers` laisse les serveurs actifs.

## Le service nrpe-server-v2 (NRPE 2.15)

Meme logique, en plus ancien : protocole v2, ADH, DH 512 statique. Permissif
par defaut comme le 4.x. Particularite : `NASTY_METACHARS` est une constante
compilee en 2.x (pas de directive de conf), donc le filtre est desactive par
un `sed` a la compilation (macro videe), pas par la config. Les arguments
passent via `--enable-command-args` + `dont_blame_nrpe=1`.
