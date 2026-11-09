# Reprise de la publication Contacts

La PR Contacts #289 et le correctif du snapshot initial #293 sont fusionnés dans
`development`. La migration Contacts est installée uniquement sur le développement
(`20261108163417`). Aucune publication web Contacts n’a été effectuée par cette tâche.

## État distant vérifié le 9 novembre 2026

Voir `checkpoint.json`. La production contient les 353 premières sources du
manifeste initial et la première étape de la source 354, enregistrée sous la version
`20261108224703`. Aucun compte Auth ni fichier Storage n’existe dans ce projet.
Le RPC de disponibilité de l’environnement et la nouvelle garde Contacts restent
absents.

Ne pas rejouer les étapes déjà enregistrées. Relire les registres avant toute reprise, car
un autre opérateur peut avoir continué l’installation.

## Refus de la revue automatique

La revue automatique a explicitement refusé `coco_initialization_source354_part02`
(`remaining/source354/part02.sql`, empreinte dans `checkpoint.json`). Elle considère
les modifications du schéma, des fonctions et des droits de production trop larges
et difficiles à annuler pour être autorisées par une demande générale de publier.
Ce refus est distinct des anciennes confirmations expirées du connecteur.

Une autorisation explicite a été demandée pour les lots 354 à 362, puis la migration
Contacts et la publication, sans copie des données de développement. Attendre la
réponse avant toute modification dépendante. Ne pas contourner le refus par SQL
brut, une autre identité, un autre canal ou un redécoupage destiné à éviter la revue.

## Préparation conservée

Après autorisation et nouvelle lecture des registres, reprendre à la deuxième étape
de la source 354, puis suivre les manifestes sous `remaining/`.
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
