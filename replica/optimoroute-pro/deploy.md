# Publication du TMS étendu

PR : https://github.com/lisciandraj/Pro-manager-Gama/pull/253

Commit de fusion initiale : `dd928cf5a2f5c9291fab298fedaf449005156740`.

## Contrôles avant publication

- 49 tests navigateur TMS réussis, dont sept nouveaux parcours.
- Tests des huit scénarios serveur du TMS étendu et de la migration sur historique peuplé réussis ; restauration du schéma complet dans une base isolée.
- Suite du dépôt exécutée : 664 tests, deux tests conditionnels ignorés. Le seul écart était le contrat de projection publique enrichi de deux indicateurs d’avis ; assertion exacte actualisée, contrôle d’indisponibilité avant livraison conservé et test de régression réussi.
- Sources, types, liens de documentation, migrations, génération reproductible et budget de démarrage vérifiés.
- Contrôle axe du calendrier et sept paires de contraste : aucune violation dans ces contrôles.
- Recherche du nom et du domaine du produit de référence dans l’artefact web : aucun résultat.
- La matrice Replica est une comparaison de fonctions documentées, pas une certification de copie intégrale ni de résultats algorithmiques identiques.

## Serveur

Migration installée : `20261027192047`, nom `tms_pro_planning_tracking`. Le fichier source a été créé par le CLI sous `20261027185533_tms_pro_planning_tracking.sql` ; le service de migration attribue sa propre version au moment de l’application.

La migration additive `tms_pro_preserve_function_dependencies` conserve aussi la liaison des politiques d’historique sur les restaurations neuves, sans écraser les wrappers plus récents.

Six nouvelles tables privées avec RLS et aucune lecture directe accordée à anon/authenticated. Façades publiques SECURITY INVOKER. L’implémentation d’autorisation d’historique réellement présente en production est conservée, y compris son durcissement du périmètre comptable.

Le contrôle de sécurité après migration ne signale aucune nouvelle alerte WARN. Les six notices INFO sont attendues pour les tables privées accessibles seulement par des fonctions autorisées.

Aucune fixture, faux départ, capture GPS ni livraison d’essai n’a été ajouté aux données de production. Aucun nouveau fournisseur, envoi automatique ou abonnement n’a été activé.

## Site

Workflow de publication : https://github.com/lisciandraj/Pro-manager-Gama/actions/workflows/deploy-coco-pages.yml

Le site doit servir une révision incluant la fusion ci-dessus et les correctifs d’historique/langue avant d’annoncer la disponibilité de l’écran **TMS → Planification et suivi**. La publication reste soumise aux jobs de construction, aux tests métier et aux parcours d’interface existants.

## Limites à suivre

GPS limité au premier plan de la PWA ; arrêter explicitement en fin de tournée. ETA et distances de repli estimées. Notifications SMS/WhatsApp manuelles conservées. Dépôts multiples et dimensions de capacité supplémentaires absents de ce lot. Fonctions partielles et absentes détaillées dans features.csv.


## Ressources additionnelles · 27 octobre 2026

- Capacités supplémentaires et lieux indépendants du conducteur, dans la marque et les droits Coco existants. Projection publique client inchangée.
- 59 parcours navigateur TMS réussis après intégration de la carte publiée par #258, y compris CSV/GPX, absence de retour général sur une fin ouverte et axe du calendrier/formulaire mobile. Les 24 contrôles d’architecture sont aussi réussis.
- Base isolée : 11 contrôles de l’extension des ressources, en plus des scénarios Pro, dispatch et trajets vérifiés. Reproduction du contournement individuel puis refus confirmé.
- Production préliminaire : contrats de fonctions attendus présents, colonne de dimensions absente avant installation, empreinte de l’autorisation d’historique conservée pour comparaison après migration.
- Construction, sources/types, liens, génération reproductible et nettoyage de marque de dist réussis. Contrôles complets et publication à confirmer avant d’annoncer cette nouvelle tranche en ligne.
- Cette extension n’active aucun fournisseur d’envoi, aucun GPS en arrière-plan et aucun service payant. Les limites restantes sont dans features.csv.


La PR de cette tranche est [#259](https://github.com/lisciandraj/Pro-manager-Gama/pull/259). La fusion conserve la mise à jour de carte #258 et raccorde son tracé facultatif aux lieux enregistrés. La vérification complète locale a progressé sans échec observé mais son processus n’a pas terminé dans l’environnement ; le statut de validation intégrale doit être celui du workflow CI, pas ce journal partiel.
