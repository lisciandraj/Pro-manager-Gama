# Reprise de la publication Contacts

La PR Contacts #289 et le correctif du snapshot initial #293 sont fusionnés dans
`development`. La migration Contacts est installée uniquement sur le développement
(`20261108163417`). La branche `production` reste figée ; aucune publication web
Contacts n’a été annoncée ni effectuée.

## État distant vérifié

Voir `checkpoint.json`. La production contient les 347 premières sources du
manifeste initial approuvé et les étapes 01 et 02 de la source 348. Ces deux étapes
ont été vérifiées dans le registre Supabase avec leurs empreintes exactes.
Aucun compte Auth ni fichier Storage n’existe dans ce projet. La fonction principale
de l’étape 03 et le RPC de disponibilité de l’environnement restent absents.

Ne pas rejouer les étapes 01 et 02. Relire les registres avant toute reprise, car
un autre opérateur peut avoir continué l’installation.

## Prochaine opération

Après rétablissement des confirmations du connecteur Supabase, appliquer
`source348/source348-part03-compact.sql` sous le nom
`coco_initialization_source348_part03`, puis l’étape 04 sous son nom enregistré.
L’alternative compacte conserve le payload canonique et les ACL finales dans
une seule transaction ; sa comparaison isolée est enregistrée dans
`source348/verification-compact.json`. Le fichier original plus long est conservé
pour comparaison, pas pour un second passage.

Continuer ensuite les sources 349 à 362 dans l’ordre des manifestes sous
`remaining/`. Le manifeste figé et ses 362 sources ne doivent pas être régénérés
depuis l’historique courant. Les fragments conservent le payload canonique et
ajoutent seulement des gardes de progression et un confinement intermédiaire
des ACL. Les résultats de comparaison du schéma, des fonctions, des ACL et des
politiques figurent dans `remaining/verification.json`.

Une confirmation expirée n’atteste aucune exécution. Vérifier les reçus et les
objets après toute réponse incertaine ; ne pas remplacer une approbation manquante
par un appel SQL brut, une autre identité ou un autre canal.

Après les 362 sources, vérifier le manifeste historique, appliquer séparément
la migration Contacts et vérifier ses fonctions, ACL, index et déclencheur.
La bascule du catalogue/portail doit être vérifiée avant l’affectation de
l’ancienne base au développement, car cette affectation refuse tout accès
non administrateur. La connexion Cloudflare n’a pas répondu à la vérification.

Affecter les environnements seulement après ces prérequis. Conserver les contrôles
CI de release et Pages, promouvoir le SHA testé par le workflow prévu, puis
vérifier les marqueurs réellement servis. Aucun contrôle de publication n’est
retiré ni contourné par ces fichiers.
