# Publication du TMS étendu

PR : https://github.com/lisciandraj/Pro-manager-Gama/pull/253

Commit de fusion : `dd928cf5a2f5c9291fab298fedaf449005156740`.

## Contrôles avant publication

- 47 tests navigateur TMS réussis, dont les cinq nouveaux parcours.
- Tests des huit scénarios serveur du TMS étendu et de la migration sur historique peuplé réussis ; restauration du schéma complet dans une base isolée.
- Suite du dépôt exécutée : 664 tests, deux tests conditionnels ignorés. Le seul écart était le contrat de projection publique enrichi de deux indicateurs d’avis ; assertion exacte actualisée, contrôle d’indisponibilité avant livraison conservé et test de régression réussi.
- Sources, types, liens de documentation, migrations, génération reproductible et budget de démarrage vérifiés.
- Contrôle axe du calendrier et sept paires de contraste : aucune violation dans ces contrôles.
- Recherche du nom et du domaine du produit de référence dans l’artefact web : aucun résultat.
- La matrice Replica est une comparaison de fonctions documentées, pas une certification de copie intégrale ni de résultats algorithmiques identiques.

## Serveur

Migration installée : `20261027192047`, nom `tms_pro_planning_tracking`. Le fichier source a été créé par le CLI sous `20261027185533_tms_pro_planning_tracking.sql` ; le service de migration attribue sa propre version au moment de l’application.

Six nouvelles tables privées avec RLS et aucune lecture directe accordée à anon/authenticated. Façades publiques SECURITY INVOKER. L’implémentation d’autorisation d’historique réellement présente en production est conservée, y compris son durcissement du périmètre comptable.

Le contrôle de sécurité après migration ne signale aucune nouvelle alerte WARN. Les six notices INFO sont attendues pour les tables privées accessibles seulement par des fonctions autorisées.

Aucune fixture, faux départ, capture GPS ni livraison d’essai n’a été ajouté aux données de production. Aucun nouveau fournisseur, envoi automatique ou abonnement n’a été activé.

## Site

Workflow de publication : https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40568415890

Le site doit servir le commit de fusion ci-dessus avant d’annoncer la disponibilité de l’écran **TMS → Planification et suivi**. La publication reste soumise aux jobs de construction, aux tests métier et aux parcours d’interface existants.

## Limites à suivre

GPS limité au premier plan de la PWA ; arrêter explicitement en fin de tournée. ETA et distances de repli estimées. Notifications SMS/WhatsApp manuelles conservées. Dépôts multiples et dimensions de capacité supplémentaires absents de ce lot. Fonctions partielles et absentes détaillées dans features.csv.
