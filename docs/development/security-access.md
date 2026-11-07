# Autorisations et exports métier — sécurité du 7 novembre 2026

La migration `20261107195204_audit_access_hardening.sql` applique trois frontières serveur. Les migrations historiques ne sont pas modifiées.

## Catalogue et Projets

Les favoris B2B appliquent `commerce_product_allowed` à `ids`, `list` et à l’ajout. Un favori enregistré avant une restriction cesse de restituer le produit et son tarif ; son retrait reste possible. L’identité client provient toujours de l’association B2B actuelle. Une entreprise ne peut pas fournir son propre identifiant pour lire les favoris d’une autre.

`pm_internal` réutilise `erp_module_allowed('projects', ...)`. La désactivation du module dans un profil retire l’accès aux RPC, tables et fichiers Projets sans modifier les règles de membre, responsable, sponsor ou viewer. La révocation est réévaluée à chaque appel ; une URL signée déjà délivrée reste soumise à sa courte durée de validité.

## Export métier limité et chiffré

L’export exige côté SQL le rôle et le module `backup`, puis l’action `backup/export`. Un administrateur pouvant gérer ses propres habilitations reste un administrateur ; cette vérification ne promet pas une séparation forte de fonctions contre lui. Le contrôle MFA récent est intégré par la politique d’identité suivante lorsqu’elle est activée.

`private.recovery_business_export_columns()` contient une liste fixe de ressources et colonnes métier revues. Les nouvelles tables et colonnes sont exclues tant qu’une migration ne les admet pas. Les clés hors ligne, configurations IA chiffrées, secrets OAuth/service, autorisations temporaires et files d’exécution ne sont pas inclus. Les copies brutes avant/après des audits sont exclues : un ancien champ sensible ne doit pas réapparaître par une copie JSON. L’identité de l’événement, l’action, l’auteur et la date restent exportables.

Les jetons de capacité publics des sondages et commandes invitées sont omis. Leurs valeurs sont régénérées par les valeurs par défaut du schéma lors d’un exercice de restauration ; les anciens liens ne sont pas réactivés. Les identifiants Auth et e-mails servent uniquement aux relations : aucun mot de passe, facteur ou session Auth n’est restauré.

Le contrat conserve `format: architect-application-export`, `version: 1`, mais déclare explicitement `scope: business_data_and_files` et `coverage.mode: business-allowlist`, avec les ressources présentes, ressources/colonnes exclues, empreinte de politique et `full_backup: false`. Les ressources exclues ne sont jamais représentées comme de fausses tables vides. Les fichiers concernent uniquement les cinq buckets métier déclarés dans le manifeste ; leur confidentialité doit être conservée lors de la reprise.

L’interface chiffre l’enveloppe complète avant le téléchargement avec AES-256-GCM, sel et IV aléatoires, PBKDF2-SHA-256 à 600 000 itérations et données associées liant format/version. La phrase de 12 caractères minimum est confirmée, reste locale et est effacée des champs après usage ou changement de session. Une réponse arrivée après déconnexion ne télécharge rien. La phrase doit être conservée dans le coffre du propriétaire : elle n’est pas récupérable par Coco.

L’enveloppe téléchargée porte `format: architect-encrypted-export`, `version: 1`. Les exports anciens en clair restent vérifiables, mais ne sont plus créés et ne sont pas restaurés automatiquement par le drill limité.

## Restauration de recette

`node scripts/restore-application-export.cjs fichier.encrypted.json --passphrase-stdin` lit la phrase sur l’entrée standard, sans argument contenant le secret. Utiliser une saisie masquée ou le mécanisme de secret du poste ; ne pas mettre la phrase dans l’historique shell. Le programme restaure uniquement une base PGlite jetable locale, jamais une connexion de production. Il refuse une politique modifiée, une ressource ou une colonne hors liste, vérifie les empreintes, les compteurs, les relations et reconstruit les séquences du périmètre restauré.

Ce fichier n’est pas une sauvegarde complète. La reprise PostgreSQL/Auth/Storage, des secrets, de la configuration et des services privés relève de la procédure [de récupération](../operations/recovery.md), avec sauvegardes chiffrées indépendantes et exercice RPO/RTO.

Déployer d’abord la migration serveur, puis les actifs ERP reconstruits. Une ancienne fonction d’export sans manifeste de portée est refusée par la nouvelle interface plutôt que téléchargée avec une promesse de sécurité incorrecte.

## Vérifications isolées

- `node --test tests/security-access-hardening-db.test.cjs` : favoris restreints/anciens, séparation clients, révocation et réactivation Projets sur RPC/SELECT/Storage, contrôle d’export et exclusion de nouvelles ressources/colonnes/copies d’audit.
- `node --test tests/security-recovery-envelope.test.cjs` : interopérabilité navigateur/CLI, mauvais secret, ciphertext modifié, nouveaux sel/IV, annulation au changement de session et lecture d’un ancien export.
- `node --test tests/p0-recovery-db.test.cjs` : exercice du périmètre métier déclaré, relations et exclusions des clés/liens publics.
