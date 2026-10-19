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
