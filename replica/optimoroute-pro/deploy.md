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

GPS limité au premier plan de la PWA ; arrêter explicitement en fin de tournée. ETA et distances de repli estimées. Notifications SMS/WhatsApp manuelles conservées. Le lot initial ne contenait pas les lieux indépendants ni les capacités supplémentaires, ajoutés dans la tranche ci-dessous. Fonctions partielles et absentes détaillées dans features.csv.


## Ressources additionnelles · 27 octobre 2026

- Capacités supplémentaires et lieux indépendants du conducteur, dans la marque et les droits Coco existants. Projection publique client inchangée.
- 59 parcours navigateur TMS réussis après intégration de la carte publiée par #258, y compris CSV/GPX, absence de retour général sur une fin ouverte et axe du calendrier/formulaire mobile. Les 24 contrôles d’architecture sont aussi réussis.
- Base isolée : 11 contrôles de l’extension des ressources, en plus des scénarios Pro, dispatch et trajets vérifiés. Reproduction du contournement individuel puis refus confirmé.
- Production préliminaire : contrats de fonctions attendus présents, colonne de dimensions absente avant installation, empreinte de l’autorisation d’historique conservée pour comparaison après migration.
- Construction, sources/types, liens, génération reproductible et nettoyage de marque de dist réussis. Contrôles complets et publication confirmés dans la vérification finale ci-dessous.
- Cette extension n’active aucun fournisseur d’envoi, aucun GPS en arrière-plan et aucun service payant. Les limites restantes sont dans features.csv.


La PR de cette tranche est [#259](https://github.com/lisciandraj/Pro-manager-Gama/pull/259). La fusion conserve la mise à jour de carte #258 et raccorde son tracé facultatif aux lieux enregistrés. La vérification complète locale a progressé sans échec observé mais son processus n’a pas terminé dans l’environnement ; le statut de validation intégrale doit être celui du workflow CI, pas ce journal partiel.


## Vérification de la tranche des ressources

Migration installée dans le registre de production : `20261027225653`, nom `tms_resource_loads_and_endpoints`. Son fichier source CLI reste `20261027204533_tms_resource_loads_and_endpoints.sql` ; aucun renommage du fichier appliqué. Les trois nouveaux déclencheurs sont présents, le planner utilise le calcul de temps partagé, la façade publique reste invocateur et les lectures directes des règles/helpers privés sont refusées. Les trois anciennes tournées conservent un instantané vide et leur fonctionnement historique.

Une enveloppe comptable d’autorisation d’historique est apparue pendant la vérification de production ; l’extension TMS ne modifie aucune fonction `coco_history_record_visible*` et conserve cette chaîne actuelle. Les avis de sécurité observés concernent la fonction administrative historique de revue et la protection des mots de passe ; aucun avis nouveau attribuable à cette extension.

PR #259 fusionnée sur `877fc1565ab7a3af21eab43bf0eccf6f636827bb`. Le workflow de la révision testée avant fusion ([40584434065](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40584434065)) a réussi ses trois jobs de contrôle : validation complète de 709 tests (707 réussis, 2 conditionnels ignorés, aucun échec), puis interfaces Agent/Comptabilité, 59 parcours TMS, 80 parcours d’historique/dossiers et les autres contrôles de publication. La suite isolée locale TMS/historique compte également 48 réussites.

Le workflow de publication de la fusion est [40599220452](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40599220452). La disponibilité réelle doit être confirmée par sa réussite et par la révision et les empreintes des actifs servis.


### Publication finale vérifiée

Le workflow `40599220452` est terminé avec succès pour les jobs métier, menus, construction et déploiement. Le site [Coco ERP](https://lisciandraj.github.io/Pro-manager-Gama/) sert effectivement la révision `877fc1565ab7a3af21eab43bf0eccf6f636827bb`, avec le même numéro de run dans `coco-build.json`.

Une vérification HTTP indépendante relit le HTML, son manifeste actif puis neuf actifs servis : `coco-tms-pro.js`, `coco-tms-gps.js`, `gama-tms-tracking.js`, `gama-tms-dispatch.js`, `coco-style-tms-module.css`, `gama-tms-module.js`, `gama-tms-driver-ui.js`, `gama-tms-execution.js` et `coco-tms-road-map.js`. Tous sont présents et leurs empreintes SHA-256 correspondent octet par octet aux sorties canoniques testées localement. Résultat : `ok=true`.

Accès : TMS → Planification et suivi → Ressources. Les quatre dimensions, les charges de livraison, les capacités véhicule et les lieux conducteur sont disponibles. Aucun faux client, ordre, départ, GPS, avis ni message de test n’a été créé en production. La parité intégrale reste limitée par les écarts explicités dans features.csv.
