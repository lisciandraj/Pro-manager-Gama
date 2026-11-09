# Reprise de la publication Contacts

La PR Contacts #289 et le correctif du snapshot initial #293 sont fusionnés dans
`development`. La migration Contacts est installée uniquement sur le développement
(`20261108163417`). Aucune publication web Contacts n’a été effectuée par cette tâche.

## État distant vérifié le 9 novembre 2026

Voir `checkpoint.json`. La production contient les 355 premières sources du
manifeste initial. Les reçus des lots 354 et 355 et leurs empreintes figurent dans
`checkpoint.json`. Le lot 356 n’a pas été appliqué. Aucun compte Auth ni fichier Storage n’existe dans ce projet.
Le RPC de disponibilité de l’environnement et la nouvelle garde Contacts restent
absents.

Ne pas rejouer les étapes déjà enregistrées. Relire les registres avant toute reprise, car
un autre opérateur peut avoir continué l’installation.

## Autorisation et blocage du connecteur

La revue automatique a explicitement refusé `coco_initialization_source354_part02`
(`remaining/source354/part02.sql`, empreinte dans `checkpoint.json`). Elle considère
les modifications du schéma, des fonctions et des droits de production trop larges
et difficiles à annuler pour être autorisées par une demande générale de publier.
Ce refus est distinct des anciennes confirmations expirées du connecteur.

Le propriétaire a ensuite répondu « Oui stp » à la question précisant les lots
354 à 362, les modifications des tables, fonctions et droits, puis la migration
Contacts et la publication, sans copie des données de développement. Cet accord
est acquis ; ne pas le redemander. La requête inchangée du lot 354 a été acceptée
et les lots 354 à 355 sont terminés.

Le connecteur a ensuite retourné trois confirmations expirées sur la requête
inchangée `coco_initialization_source356_part01`. Les lectures fonctionnent et le
registre confirme l’absence d’application. Ne pas réessayer en boucle ni forcer
l’exécution par un autre canal. Aucun refus de risque supplémentaire n’a été
renvoyé pour ce lot ; le blocage actuel est distinct de l’accord utilisateur.

## Préparation conservée

Après rétablissement du connecteur et nouvelle lecture des registres, reprendre à
la première étape de la source 356, puis suivre les manifestes sous `remaining/`.
Le manifeste figé et ses 362 sources ne doivent pas être régénérés
depuis l’historique courant. Les fragments conservent le payload canonique et
ajoutent seulement des gardes de progression et un confinement intermédiaire
des ACL. Les résultats de comparaison du schéma, des fonctions, des ACL et des
politiques figurent dans `remaining/verification.json`.

Une confirmation expirée n’atteste aucune exécution. Vérifier les reçus et les
objets après toute réponse incertaine.

Après les 362 sources, vérifier le manifeste historique, appliquer séparément
la migration Contacts et vérifier ses fonctions, ACL, index et déclencheur.
La bascule du catalogue/portail doit être vérifiée avant l’affectation de
l’ancienne base au développement, car cette affectation refuse tout accès
non administrateur. La connexion Cloudflare fonctionne de nouveau ; le contrôle
des assets Pages avec un JWT de téléversement frais renvoie encore HTTP 403,
code 8000013. Aucun téléversement d’assets ni nouveau déploiement Cloudflare
n’a été effectué.

Affecter les environnements seulement après ces prérequis. Conserver les contrôles
CI de release et Pages, promouvoir le SHA testé par le workflow prévu, puis
vérifier les marqueurs réellement servis. Aucun contrôle de publication n’est
retiré ni contourné par ces fichiers. Aucune donnée de développement n’est copiée.

Le paquet storefront validé est conservé hors Git sous
`/workspace/artifacts/gama-storefront-production-aae3ba9c.zip` ; ses instructions
Wrangler et ses empreintes sont incluses. Il contient uniquement les fichiers
publics et le Worker compilé, sans secret. L’interface Cloudflare native ne permet
pas de fournir le JWT requis par l’API d’assets. Le transfert de ce JWT vers un
terminal a été refusé séparément ; ne pas retenter ce canal. Aucun secret n’a été
transmis et aucun déploiement n’a été effectué.

Le candidat testé reste `aae3ba9c76fd40daa1aac8293a63ad9aef1fd2b9` ; le
Développement actuel contient d’autres modifications qui ne doivent pas être
substituées automatiquement à cette release. La branche Production vérifiée
reste `20272ccbd040a5a00b32d6632ba8ad9eb1b72481`.
