# Récupération de Coco ERP

Mise à jour : 19 octobre 2026. Aucun exercice de restauration de données réelles n’est attesté par ce document.

## Copie récupérable

`python scripts/backup-coco.py` vérifie les prérequis sans se connecter. Le mode `--run --destination <nouveau-dossier>` exporte PostgreSQL avec `pg_dump 17`, chiffre immédiatement avec `age`, copie et chiffre chaque objet Storage, puis chiffre un manifeste contenant leurs chemins, empreintes, métadonnées de buckets et configurations JSON versionnées. Aucun dump en clair n’est créé. Les identifiants passent par des variables d’environnement, pas des arguments ou des journaux.

Les prérequis manquants dans la session d’implémentation sont `COCO_DATABASE_URL`, `COCO_SUPABASE_URL`, `COCO_SERVICE_KEY` et la clé publique `COCO_AGE_RECIPIENT`, ainsi que les exécutables `pg_dump` et `age`. Le propriétaire conserve la clé privée age hors du serveur et teste sa récupération avec un second responsable. Ne jamais ajouter ces secrets au dépôt.

Configurer un ordonnanceur existant avec ce script sur un hôte privé administré, une destination chiffrée hors de Supabase et une alerte de sortie non nulle. Une copie sans `COMPLETE.json` est incomplète. Conserver par exemple 24 copies horaires, 30 quotidiennes et 12 mensuelles après validation du coût et des besoins. Ces paramètres sont proposés, pas activés. La fréquence réelle et la durée des exports devront permettre de valider le RPO ; aucune garantie d’une heure n’est revendiquée.

Une sauvegarde de base n’inclut pas les octets Storage. Une copie de Git ne sauvegarde pas les données métier. Les secrets du service SRI, de Cloudflare, du fournisseur de mail, les paramètres Auth/DNS et les certificats fiscaux doivent être exportés séparément dans le coffre administrateur. L’inventaire doit nommer un responsable et une procédure de renouvellement pour chacun.

## Exercice de restauration isolé

1. Choisir une copie complète ; vérifier l’empreinte du manifeste chiffré et déchiffrer celui-ci uniquement sur un hôte privé avec la clé age. Vérifier toutes les empreintes avant restauration.
2. Créer une instance PostgreSQL 17 et des services Auth/Storage isolés. Bloquer les connexions sortantes au niveau réseau avant toute restauration : SRI, paiement, mail, webhooks et tâches ne doivent jamais atteindre la production. Ne pas utiliser le projet `mknsaibrewksgomuslev`.
3. Examiner `pg_restore --list` sur le dump déchiffré en flux, vérifier la compatibilité des extensions et des rôles. Restaurer selon la procédure Supabase correspondant à la version observée. Désactiver Cron/automatisations et remplacer les secrets et URL d’intégration avant de rendre l’environnement accessible. Un simple chargement PGlite ne valide pas ces services.
4. Recréer les buckets et réimporter les objets à leurs noms originaux. Reconstituer leurs métadonnées et permissions sans rendre publics les documents privés. Restaurer la configuration Auth avec des comptes de recette ; ne pas envoyer de récupération de mot de passe à de vrais utilisateurs.
5. Comparer les comptages et sommes de contrôle : produits, contacts, commandes, quantités physiques/réservées, mouvements, factures, paiements, écritures équilibrées et objets Storage. Tester une connexion de recette, une pièce jointe, une facture et une livraison ; vérifier le refus entre deux clients.
6. Mesurer l’âge de la dernière transaction récupérée (RPO) et le temps jusqu’aux parcours utilisables (RTO). Proposition métier à valider : transactions ≤1 h, documents/configuration ≤24 h, rétablissement ≤4 h. Archiver le compte rendu, la version de code, le registre de migrations et les écarts.

## Livraison et retour arrière

Le registre distant observé est conservé dans `supabase/production-baseline-20261019.json`. Les anciens resets ont été déplacés vers `historical-operations/`. Ne pas lancer `db push --include-all` ou `migration repair` pour résoudre les différences de nom. Vérifier un export récent du registre avec `scripts/migration-preflight.cjs` et le manifeste de livraison. Appliquer uniquement le fichier explicitement revu, puis enregistrer le timestamp et l’empreinte réellement retournés par Supabase.

Le catalogue possède une restauration de fonction avec garde d’empreinte dans `docs/audits/proposals/coco-storefront-projection-rollback.sql`. Les nouvelles tables de clés hors ligne et d’approbation ne doivent pas être supprimées lors d’un retour de code : elles peuvent contenir les seules clés permettant de récupérer des preuves en attente. En cas d’incident Agent Coco, conserver la lecture et désactiver les écritures ; ne pas réactiver l’ancien protocole auto-confirmé.

Pour le code, republier un artefact testé portant son SHA. Vérifier `coco-build.json`, les ressources hachées et l’ouverture des modules sur une PWA déjà installée. Cloudflare Pages et GitHub Pages sont deux publications distinctes. Ne pas restaurer la base pour un simple retour de fichiers statiques.

## Outillage opérationnel — 7 novembre 2026

Les sauvegardes nouvelles utilisent un manifeste chiffré de version 2 et un `COMPLETE.json` atomique, synchronisé sur disque, contenant les empreintes des **fichiers chiffrés**. Le répertoire doit être privé et nouveau ; aucun artefact terminé n’est remplacé. Un échec laisse une copie incomplète sans attestation de complétude. Les empreintes détectent une corruption ; elles ne constituent pas une signature d’origine contre un administrateur capable de remplacer à la fois les fichiers et le manifeste. La copie immuable indépendante et le contrôle des droits de destination restent nécessaires. La supervision refuse les liens symboliques, les fichiers modifiés, les chemins d’artefact inattendus et les copies anciennes. Les anciens exports restent conservés ; ils demandent une vérification de format par l’opérateur et ne sont pas supprimés par la nouvelle rétention.

### Installer la planification

`operations/systemd/` contient les services et minuteries pour sauvegarde, fraîcheur, rétention à blanc et supervision de compteurs. Ils sont fournis comme configuration révisable ; aucun hôte privé ni ordonnanceur n’a été configuré par cette intervention.

Sur un hôte privé administré, provisionner un compte `coco-backup` sans connexion interactive, PostgreSQL client **17**, `age`, les sources revues sous `/opt/coco`, et une destination **hors du fournisseur de la base** montée sous `/srv/coco-backups`, propriétaire `coco-backup`, mode 0700. L’attestation `COCO_BACKUP_LOCATION_ATTESTED=off-provider` est une déclaration de l’opérateur, pas une détection automatique du fournisseur. Une copie immuable/versionnée et une identité de conservation séparée doivent être configurées sur ce stockage ; un répertoire local ne fournit pas à lui seul la protection contre une suppression malveillante.

Copier le modèle `backup.env.example` vers `/etc/coco/backup.env` (root 0600, lu par systemd avant le changement d’utilisateur), renseigner les secrets dans le coffre privé et les fichiers inventoriés en mode 0600 accessibles au seul compte de sauvegarde. Ne pas mettre leurs valeurs dans la commande, le dépôt ou un journal. Les fichiers de certificat et configurations doivent avoir un propriétaire identifié et leur export actualisé par le responsable de chaque fournisseur.

Le modèle `vault-assets.example.json` énumère séparément Auth, DNS, certificat/configuration SRI et secrets des fournisseurs. L’inventaire réel est privé ; le script exige des chemins absolus de fichiers réguliers privés, interdit les liens et limite chaque actif à 100 Mio. Chaque actif est chiffré séparément sous un nom neutre ; ses chemins privés ne figurent pas dans le marqueur clair. Le mode planifié exige cet inventaire pour ne pas annoncer une sauvegarde complète de la pile sans ses composants hors base. L’inventaire doit être approuvé pour sa complétude ; le script ne peut pas deviner un secret absent.

```sh
python3 scripts/coco-operations.py backup --root /srv/coco-backups
python3 scripts/coco-operations.py backup --root /srv/coco-backups --run
python3 scripts/coco-operations.py check --root /srv/coco-backups --max-age-hours 26
```

Après une première copie vérifiée et le test du canal d’alerte existant, installer les unités révisées puis activer `coco-backup.timer` et `coco-backup-check.timer`. Le modèle quotidien à 02:00 UTC et la fenêtre de fraîcheur de 26 heures sont un point de départ technique à faire approuver : ils ne garantissent pas un RPO d’une heure. Observer la durée réelle, les copies complètes et les alertes de copie manquante ; adapter ensemble fréquence et fenêtre. Un service lancé ne prouve pas la réception d’une alerte par une personne.

Pour la rétention, remplir une politique privée approuvée à partir de `backup-retention.example.json`, avec durée et nombre minimal de copies. `retention --root <destination> --policy <politique>` ne supprime rien. `--apply` ne doit être ajouté qu’après contrôle d’une copie indépendante/immuable, de la politique et du résultat à blanc. Il ne supprime que les artefacts chiffrés d’une copie complète intégralement vérifiée, en conservant le nombre minimal ; aucun document métier ou export partiel n’est purgé.

### Répéter la restauration hors réseau

`coco-restore-drill.py` vérifie d’abord les empreintes chiffrées sans déchiffrer ni contacter un service :

```sh
python3 scripts/coco-restore-drill.py --bundle <copie-privee> --output <nouveau-rapport-prive.json>
```

Le mode `--run --confirm-isolated --identity <fichier-age-prive>` exige **un espace de noms réseau ne contenant que l’interface `lo`**. Les cibles sont uniquement `127.0.0.1`, `::1` ou `localhost` ; la base doit s’appeler `coco_restore_*`. Le processus Python doit être démarré dans ce même espace de noms ; un indicateur d’environnement déclaratif ne suffit pas. Les variables sont `COCO_RESTORE_DATABASE_URL`, `COCO_RESTORE_STORAGE_URL` et `COCO_RESTORE_SERVICE_KEY`, propres à la pile jetable locale. Les options de redirection et les variables libpq héritées ne peuvent pas choisir une autre cible. Le projet Supabase de production et tout hôte distant sont refusés. Ne pas rendre le réseau sortant accessible après import tant que les tâches, secrets et intégrations n’ont pas été neutralisés.

L’opérateur doit provisionner PostgreSQL 17 **et les services Auth/Storage de recette** dans cet espace isolé avant exécution. Le dump est déchiffré directement vers `pg_restore`, sans fichier SQL clair. Les objets Storage sont recréés dans des buckets privés et les actifs de coffre restent chiffrés sans activation automatique. Le rapport final reste `application_acceptance_required` : il ne certifie ni connexion Auth, ni configuration du signataire, ni RPO/RTO. Les essais des étapes 4–6 ci-dessus, les comparaisons métier, les refus entre clients et le test fiscal `pruebas` avec données factices doivent être consignés séparément. Une erreur laisse la pile de recette à détruire/recréer ; aucune instruction ne nettoie ni remplace une base existante de production.

Validation locale de l’outillage : `python3 -m unittest discover -s tests -p 'test_coco_operations.py' -v`. Ces tests utilisent uniquement fichiers et identités factices et des appels réseau/processus simulés. Aucun export, déchiffrement ou exercice sur données réelles n’a été exécuté ici. La supervision et la réponse aux incidents sont détaillées dans [security-monitoring.md](security-monitoring.md).

### Livraison chiffrée vers Google Drive

La destination choisie est le dossier privé **« Coco ERP - sécurité »**. Son ID doit être lu dans le dossier réellement vérifié, puis renseigné dans `COCO_DRIVE_FOLDER_ID`. Aucun ID n’est fourni ou inventé dans le modèle et cette intégration n’est pas activée : il reste à vérifier/créer le dossier, provisionner les accès du serveur privé, exécuter une première copie et son contrôle. Aucun transfert de données réelles n’a été effectué pendant l’implémentation.

`scripts/coco_drive_backup.py` utilise uniquement la bibliothèque standard Python et l’API HTTPS Google Drive v3. Avant toute requête, il vérifie la copie complète, les empreintes et l’enveloppe binaire age des fichiers privés. Il ne transfère que les artefacts `.age` explicitement inventoriés : ni dump clair, ni `COMPLETE.json` clair, ni fichier voisin ou identité privée age. Le manifeste métier, les chemins Storage et les actifs de coffre restent chiffrés. **Ne jamais inclure l’identité privée age dans l’inventaire du coffre** ; elle reste indépendante du serveur de sauvegarde.

Le serveur exige un dossier accessible en écriture dont les permissions ne contiennent aucun accès `anyone` ou `domain`. Les utilisateurs et groupes explicitement autorisés restent sous la responsabilité du propriétaire. L’outil ne crée et ne modifie aucun partage. Il crée un sous-dossier par tentative avec l’état `pending`, transfère les fichiers par blocs de 8 Mio via des sessions reprenables, puis contrôle les tailles et les sommes de contrôle calculées par Drive : SHA-256 lorsque disponible, sinon MD5 comparé aux octets chiffrés locaux. Une seconde lecture de la liste distante doit correspondre exactement aux fichiers attendus avant de publier l’état `complete`. Les identifiants de session sont limités au point d’entrée Google fixe ; les redirections sont refusées. Aucune relance réseau automatique n’est effectuée ; une erreur interrompt le job et laisse le dossier partiel à l’état `pending`. Une nouvelle tentative peut créer un second dossier du même nom ; aucun dossier distant n’est supprimé automatiquement.

Configurer **une seule** source de jeton : `COCO_DRIVE_ACCESS_TOKEN` dans l’environnement privé chargé par systemd, ou `COCO_DRIVE_TOKEN_FILE`, chemin absolu d’un fichier contenant uniquement le jeton d’accès courant. Ce fichier doit appartenir à `coco-backup`, être régulier, sans lien, en mode 0600 ou 0400. Le modèle sélectionne `/etc/coco/drive-access-token`. Ne jamais y placer une identité age, un JSON de compte de service ou un jeton de rafraîchissement. Le code ne lance aucun flux OAuth et ne renouvelle pas les accès : le mécanisme privé d’authentification/renouvellement du serveur doit fournir un jeton valide avant chaque exécution. Les identifiants OAuth durables restent dans le coffre et hors de l’inventaire téléversé. Utiliser une identité dédiée limitée au dossier ; avec `drive.file`, le dossier doit avoir été explicitement autorisé à la même application OAuth. Un compte de service sans quota Drive ne peut pas déposer de fichiers dans un simple dossier My Drive ; son usage exige une configuration Google Workspace adaptée, par exemple un Drive partagé.

Les unités fournies exigent maintenant `--drive` pour la sauvegarde **et** sa supervision. La réussite du job est conditionnée à la confirmation distante et à l’écriture d’un reçu privé, hors de la copie, sous `/srv/coco-backups/.drive-receipts/`. Le reçu lie le dossier de destination à l’empreinte de l’ensemble local. `check --drive` exige un reçu récent lié à une copie encore vérifiable ; une copie locale récente seule ne suffit pas. Ce reçu atteste la vérification au moment du transfert ; il ne constitue pas un contrôle en temps réel de la disponibilité Drive. Le service `OnFailure` conserve l’alerte existante en cas d’échec de transfert. Le stockage hors du fournisseur, l’attestation de l’opérateur et les règles de rétention existantes sont toujours requis. Une copie Drive ne fournit pas d’immuabilité contre la suppression par un compte qui possède le droit d’effacer.

```sh
# Préparation sans réseau ; ne lit aucun jeton et n’exporte aucune donnée.
python3 scripts/coco-operations.py backup --root /srv/coco-backups --drive
python3 scripts/coco-operations.py drive-upload --bundle /srv/coco-backups/backup-YYYYMMDDTHHMMSSZ-xxxxxxxx
# Après configuration privée et vérification de la destination :
python3 scripts/coco-operations.py backup --root /srv/coco-backups --run --drive
python3 scripts/coco-operations.py check --root /srv/coco-backups --max-age-hours 26 --drive
# Reprendre une copie locale complète après un échec de transfert :
python3 scripts/coco-operations.py drive-upload --bundle /srv/coco-backups/backup-YYYYMMDDTHHMMSSZ-xxxxxxxx --run
```

Avant activation des minuteries, vérifier une copie avec le même accès OAuth : le sous-dossier doit avoir `appProperties.coco_state=complete`, le bon `coco_set_sha256` et la liste exacte des artefacts chiffrés. Ces propriétés sont des métadonnées techniques neutres privées à l’application OAuth, pas un fichier métier en clair. Conserver l’accès de récupération à cette application séparément du jeton temporaire du serveur. Pour rapatrier une copie, télécharger les fichiers chiffrés d’un sous-dossier complet dans un répertoire privé 0700 portant son nom d’origine, puis lire ses métadonnées avec les champs `id,name,parents,mimeType,trashed,appProperties` via la même application OAuth. Enregistrer ce JSON en mode 0600 **hors** du répertoire des artefacts.

La commande suivante reconstitue le marqueur local `COMPLETE.json` sans jeton ni accès réseau. Elle exige le bon parent configuré par `COCO_DRIVE_FOLDER_ID`, un sous-dossier distant attesté complet, les fichiers exacts privés et leur enveloppe age. Les empreintes SHA-256 recalculées doivent reproduire `coco_set_sha256` avant toute écriture. Le mode par défaut vérifie seulement ; `--apply` crée le marqueur atomique puis appelle `verify_bundle()`. Une copie altérée ou partielle reste refusée.

```sh
python3 scripts/coco-operations.py drive-recover-marker --bundle /srv/coco-backups/backup-YYYYMMDDTHHMMSSZ-xxxxxxxx --folder-metadata /etc/coco/recovery-folder-metadata.json
python3 scripts/coco-operations.py drive-recover-marker --bundle /srv/coco-backups/backup-YYYYMMDDTHHMMSSZ-xxxxxxxx --folder-metadata /etc/coco/recovery-folder-metadata.json --apply
```

L’exercice de restauration isolé peut ensuite consommer cette copie. Le téléchargement reste une étape opérateur à inclure au premier exercice réel ; le parcours simulé téléversement → rapatriement → reconstruction → `verify_bundle()` est testé sans données réelles. Aucun essai réel n’est attesté ici.

Validation sans réseau : `python3 -m unittest discover -s tests -p 'test_coco_drive_backup.py' -v`. Les tests HTTP simulés vérifient notamment un transfert en plusieurs blocs avec réponse 308, le refus des URL de session étrangères, des jeux incomplets ou non chiffrés, des liens, des permissions publiques, des mauvaises sommes de contrôle et des ensembles distants partiels. Ils vérifient aussi que le job échoue et qu’aucun état distant complet n’est publié en cas d’erreur.
