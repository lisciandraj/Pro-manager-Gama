# Serveur routier privé pour Coco TMS

Ce paquet complète [l’optimisation routière](../../docs/development/tms-road-optimization.md) déjà publiée. Il prépare un serveur **OSRM privé**, profil voiture, algorithme CH, compatible avec les distances et les durées demandées par l’Edge Function `tms-routing`.

Il ne crée pas d’hébergement, d’abonnement ou de livraison ERP. Le compte Cloudflare consulté le 30 octobre 2026 ne dispose pas de Workers Paid : l’API Containers refuse donc le déploiement. Un serveur Linux de GAMA ou un VPS reste à fournir. L’activation effective ne doit pas être annoncée avant le contrôle HTTPS et le raccordement des secrets Supabase.

## Prérequis et dimensionnement

- Hôte Linux amd64 ou arm64 avec Docker et Docker Compose **2.24.4 ou plus récent**, Python **3.12 ou plus récent**, Node.js **22**.
- Nom DNS dédié dont les enregistrements A/AAAA pointent réellement vers cet hôte ; ports TCP 80 et 443 disponibles. Le serveur doit pouvoir joindre les autorités ACME pour son certificat.
- Répertoire de travail sans espaces ni syntaxe dotenv dans son chemin, sur un disque persistant. Les secrets et données restent dans `services/tms-routing/.runtime/`, exclu de Git ; les fichiers de secrets sont créés en mode `0600`.
- Le routage et le prétraitement sont bornés par défaut à 2 CPU et 4 Gio. Ce sont des limites de protection, pas une garantie de dimensionnement pour l’extrait Équateur. Réserver les ressources du système et des autres applications ; mesurer mémoire, disque, temps de préparation et temps de réponse sur l’extrait réel avant d’accepter l’exploitation. Préparer le graphe sur une machine séparée si nécessaire.
- Sauvegarder les données ACME et le dernier graphe validé ; assurer la supervision et les mises à jour. L’hébergeur et les éventuels proxies doivent aussi désactiver leurs journaux d’URL contenant les coordonnées.

Les images OSRM et Caddy sont figées **par digest** dans [images.json](deploy/images.json). Le script choisit l’architecture locale. OSRM 26.10.0 et Caddy 2.11.7 sont les versions examinées ; les images doivent rester à jour par changement explicite des empreintes et nouvelle validation. Le prétraitement et le serveur utilisent exactement la même image OSRM.

## Installation sur le serveur choisi

Les commandes partent de la racine d’une copie du dépôt. Remplacer le domaine et le contact de certificat par les valeurs réelles.

```sh
python3 services/tms-routing/deploy/prepare.py init \
  --host routes.domaine-gama.example --email exploitation@domaine-gama.example
```

Cette commande génère un jeton aléatoire de 256 bits dans le fichier privé `server.env`. Elle refuse un nom d’hôte contenant protocole, port, chemin, caractères de configuration ou adresse IP, et refuse d’écraser des identifiants existants. Ne jamais copier ce fichier dans un ticket, un commit ou une conversation.

Préparer ensuite le graphe de l’Équateur :

```sh
python3 services/tms-routing/deploy/prepare.py prepare --ecuador --memory 4g
```

Le téléchargement provient de Geofabrik en HTTPS ; sa somme publiée détecte un transfert incomplet. Le manifeste capture également le SHA-256 exact du fichier, l’image OSRM, le profil, l’algorithme et la version calculée. Le prétraitement s’exécute sans réseau dans un dossier neuf. Un serveur candidat, accessible uniquement sur `127.0.0.1`, vérifie ensuite la réponse Table sur des points publics de Quito, sans données clients.

Un échec conserve la configuration précédente. Une réussite sélectionne le nouveau dossier immuable dans `server.env` ; elle ne redémarre pas un serveur existant. Les anciens graphes restent disponibles pour un retour arrière et doivent être purgés explicitement lorsque la nouvelle version est acceptée. Le plafond de téléchargement est de 2 Gio ; le disque de travail doit accueillir à la fois l’entrée, le nouveau graphe et le graphe précédent.

Publier le serveur HTTPS :

```sh
docker compose --env-file services/tms-routing/.runtime/server.env \
  -f services/tms-routing/deploy/compose.yml up -d
python3 services/tms-routing/deploy/prepare.py check
```

Le contrôle HTTPS vérifie le jeton, le refus des appels anonymes et des autres API OSRM, la version annoncée, les distances et les durées. Il écrit **seulement après réussite** le fichier privé `services/tms-routing/.runtime/supabase.env`.

Le port 5000 n’est pas publié. OSRM reste dans un réseau Docker interne ; ses fichiers sont montés en lecture seule. Le proxy ne transmet que les requêtes GET authentifiées vers `/table/v1/driving/…`, retire le jeton avant OSRM et interdit la mise en cache HTTP. Les journaux d’accès et d’erreur HTTP du proxy sont désactivés ; les deux conteneurs utilisent également le pilote Docker `none` pour éviter d’enregistrer les URL.

## Raccordement à Coco

Depuis une session CLI Supabase autorisée pour le projet GAMA, après vérification de sa version et de `supabase secrets set --help` :

```sh
supabase secrets set --project-ref mknsaibrewksgomuslev \
  --env-file services/tms-routing/.runtime/supabase.env
```

L’autre possibilité est de définir ces trois secrets dans la configuration des Edge Functions du projet Supabase :

| Secret | Origine |
| --- | --- |
| `TMS_OSRM_URL` | URL HTTPS du serveur validé |
| `TMS_OSRM_TOKEN` | Jeton privé généré ; jamais une clé client publique |
| `TMS_ROAD_DATA_VERSION` | Version exacte du graphe validé |

Le connecteur actuel ne permet pas de modifier directement ces secrets. Ne pas contourner ce manque en plaçant le jeton dans le JavaScript, la configuration publique du site ou les arguments d’une commande.

Dans Coco → TMS → Planifier, **Optimiser avec les temps routiers** doit alors afficher **Matrice routière privée** et sa date. Vérifier les sens uniques, accès, retours et créneaux sur un échantillon métier avant de se servir des ETA pour l’exploitation. Le graphe et les temps restent sans trafic en direct, sans profil poids lourd et sans garantie d’optimum global.

## Mise à jour et reprise

Rejouer la préparation lors d’une mise à jour de l’extrait ou de l’image, puis redémarrer avec la même commande Compose, exécuter le contrôle HTTPS et remettre les trois secrets Supabase à jour. Le digest logiciel et le SHA-256 du fichier OSM participent à la version : le cache de matrice ne doit pas mélanger deux graphes. Conserver le dernier `server.env` dans une sauvegarde privée avant une activation. Pour revenir en arrière, restaurer ce fichier privé, relancer Compose, vérifier HTTPS et restaurer la version correspondante dans Supabase.

Superviser la disponibilité avec `prepare.py check` depuis un système autorisé ; les résultats affichent seulement des nombres de lieux, de cellules, de requêtes, des durées et la version. Ne pas activer un journal HTTP détaillé pour dépanner : les coordonnées figurent dans le chemin du protocole OSRM. L’application garde son repli estimé si le service ne répond pas ou si la matrice est invalide.

## Validation isolée du paquet

```sh
node --test tests/tms-road-service.test.mjs
python3 tests/tms-road-service-integration.py
```

Le deuxième test exige Docker. Il génère un réseau OSM synthétique de 120 points, des rues à sens unique et des liaisons bidirectionnelles. Il exécute les **véritables images figées** avec le fichier Compose de production et une surcharge réservée au test : HTTP uniquement sur une adresse loopback, aucun domaine ni certificat public. Il vérifie les matrices 20/50/100, le proxy authentifié, la version, les volumes en lecture seule, l’absence de port OSRM public et les pilotes de journalisation. Les conteneurs et volumes de ce projet isolé sont supprimés à la fin.

Le workflow [Validate private TMS road service](../../.github/workflows/tms-road-service.yml) conserve uniquement un rapport JSON sans secrets ni coordonnées. Ce contrôle vérifie l’intégration serveur ; les comparaisons de tournées avant/après restent dans le [benchmark du planificateur](../../replica/tms-routing/benchmark.json). Aucun de ces essais ne valide un hébergement permanent, le réseau réel de Quito ou le trafic.

Sources primaires : [OSRM 26.10.0](https://github.com/Project-OSRM/osrm-backend/releases/tag/v26.10.0), [images officielles OSRM](https://github.com/Project-OSRM/osrm-backend/pkgs/container/osrm-backend), [Caddy 2.11.7](https://github.com/caddyserver/caddy/releases/tag/v2.11.7), [extraits Geofabrik](https://download.geofabrik.de/south-america/ecuador.html), [Caddy et journaux](https://caddyserver.com/docs/caddyfile/options#log).
