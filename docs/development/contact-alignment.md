# Alignement des données Contacts — 16 octobre 2026

## Contrat

Le formulaire Contacts « Modifier » utilise un vocabulaire commun pour clients, fournisseurs et interlocuteurs de clients/prospects : identification, deux téléphones, e-mail, adresse structurée, coordonnées GPS, site web, secteur et langue. La création de clients conserve l’identifiant obligatoire de main ; les anciennes fiches sans identifiant restent modifiables. Les validations lors des opérations fiscales restent en place. Le nom dans la liste ouvre le dossier du tiers.

Seul un `contact_entity_id` déjà partagé constitue une identité commune. Aucun rapprochement par nom, e-mail, RUC ou téléphone ne crée de lien. Les modifications des champs communs sont synchronisées côté serveur, y compris depuis les anciens formulaires et imports. Notes, statut actif, tarifs, conditions de paiement, crédit, contacts de réception et appartenance au portail ne sont pas copiés entre rôles. Les documents et leurs instantanés ne sont pas réécrits.

Un interlocuteur reste une personne distincte : ses téléphones, son e-mail et son identité ne sont pas remplacés par ceux de l'entreprise. Son adresse peut être héritée de l'entreprise (projection en lecture) ou indépendante. L'adresse héritée suit les changements du parent sans être recopiée dans la fiche personnelle. Changer d'adresse sans remplacer les coordonnées invalide l'ancienne position GPS.

## Écritures et conflits

`coco_contact_record` fournit la fiche courante, sa version et l'adresse héritée autorisée. `coco_contact_save` utilise une liste de champs autorisés, une version optimiste et une transaction. Les champs absents restent inchangés ; un `null` explicite efface un champ facultatif. Les contrôles RLS et d'actions des rôles liés s'appliquent à toute propagation ; un refus annule la transaction.

La reprise initiale remplit seulement les valeurs communes non ambiguës. Les contradictions restent intactes et sont signalées. `coco_contact_compare` et `coco_contact_resolve` permettent un choix explicite, justifié et versionné ; adresse et identification sont comparées par blocs cohérents. La sauvegarde privée `private.coco_contact_alignment_backup`, protégée par RLS et sans droit applicatif, conserve l'état avant reprise. Elle reste dans la base, jamais dans Git.

## Historique et validation

La migration `20261016160823_coco_contact_alignment.sql` a été installée dans Supabase. Son SHA-256 est `7ed58c4e6c161ab041ffe28530cf55f925d1dfea297d52f659178ffce54b2f8b`. Le SQL exact du précédent lot Contacts, version `20261015202048`, est désormais inclus dans la reconstruction avec les mêmes octets que l'archive ; il n'a pas été rejoué en production. Le vérificateur contrôle aussi les manifestes d'archives quand leur fichier est présent dans `supabase/migrations`.

La suite locale a obtenu 411 réussites, zéro échec et un test ignoré. Les tests SQL spécifiques couvrent la reprise, la synchronisation bidirectionnelle, les valeurs absentes, les conflits, les autorisations et les adresses personnelles. Les tests navigateur couvrent les formulaires à 390, 820 et 1280 pixels, les sauvegardes concurrentes et l'ouverture du dossier. Leur résultat final et la publication de l'interface sont à vérifier dans les workflows du commit livré ; une migration installée n'est pas une preuve de publication frontend.

## Intégration du 21 octobre 2026

Les conflits avec main sont résolus en conservant les adresses de livraison, les comptes portail, les retours de fermeture et les coordonnées GPS asynchrones. Les deux migrations installées sont restaurées byte-identiques dans le dépôt, sans exécution en production. Les tests Contacts sont aussi déclenchés sur pull request. La validation et le SHA effectivement servi sont contrôlés avant annonce de publication.
