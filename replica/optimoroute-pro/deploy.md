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

Reprise commune : migration des ressources `20261027225653` installée et SQL
exact archivé ; empreintes historiques inchangées, sans modifier les données
de tournée. L'interface de ce complément est intégrée à main par #259 ; la reprise
commune conserve son code et vérifiera le commit servi après sa publication. Voir [l'état consolidé](../integration-2026-10-27/README.md).


## Aide au départ différé · 28 octobre 2026

La PR [#264](https://github.com/lisciandraj/Pro-manager-Gama/pull/264) ajoute une proposition manuelle dans l’éditeur d’horaire vérifié. Le clic prépare une heure plus tardive, sans sauvegarde ni recalcul automatique global. La validation serveur existante recalcule les contraintes lors de la confirmation ; aucune migration ni écriture métier de production n’est exécutée par cette installation.

Révision testée : `a6c51778acc4b8ab58a7b2937762ff0849cacfbf`, arbre `9ccf8afe8d70a3382eeec02edf502b7f7dc4c64b`. CI [40717096611](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40717096611) réussie : 728 tests de validation (726 réussis, deux conditionnels ignorés), 27 parcours Coco Clair et 65 parcours TMS, dont six nouveaux cas. Les neuf tests serveur dispatch/trajets vérifiés sont aussi réussis localement. Le navigateur local n’a pas pu être téléchargé ; les résultats d’interface proviennent de la CI.

Fusion : `bf7445b198b6f8958e08ffcbf9d80a357220d0f8`. Publication réussie dans [40719428685](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40719428685) : construction, métier, menus et déploiement sont tous réussis. La présentation Coco Clair actuelle et les fonctionnalités précédentes sont conservées.


Vérification HTTP indépendante : `coco-build.json` sert `bf7445b198b6f8958e08ffcbf9d80a357220d0f8` et le run `40719428685`. Le manifeste actif référence le nouveau `gama-tms-execution.js` ; son empreinte SHA-256 correspond exactement au fichier testé et le contrôle `data-suggest-start` est présent. Accès : ouvrir l’horaire d’une tournée contenant une attente vérifiée à sa première livraison. Cette proposition reste à confirmer ; le démarrage flexible automatique global demeure absent de la matrice.
