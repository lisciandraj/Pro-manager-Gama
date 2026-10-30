# Défauts reproduits

- TMS-R01 · S2 · Avec 100 tâches, 5 conducteurs, équilibrage par arrêts et tâches réservées à un conducteur, le moteur historique pouvait remplir celui-ci de tâches génériques et laisser quatre tâches en attente. Reproduit dans le benchmark isolé : 96/100. Correction : à priorité identique, réserver d’abord le conducteur imposé ; résultat 100/100.
- TMS-R02 · S2 · Durant le développement, une fenêtre horaire convertie en nombre JSON décimal provoquait une erreur de conversion entière. Reproduit par le test base 20 livraisons. Correction : conversion numérique explicite dans l’évaluateur ; régression conservée.

- TMS-R03 · S2 · Le départ d’un camion pouvait invalider une matrice encore valable pour les points restants et faire replanifier les autres tournées sur estimation. Test de régression reproduit en base avant correction : mode `estimated` au lieu de `road`. Correction : vérifier la couverture exacte des coordonnées requises dans le cache, sans exiger de conserver les points retirés.

Les trois corrections font partie du commit de cette livraison. Aucun S1 ouvert dans ce périmètre. L’activation et la qualité du graphe privé restent à valider avec l’hébergeur choisi ; elles ne sont pas simulées comme opérationnelles.

Les essais navigateur complets lancés en parallèle de la suite SQL ont rencontré des délais de 30 s sur des parcours existants. Les quatre cas ont ensuite réussi avec un seul navigateur et une limite de 60 s (71 parcours distincts validés au total). Les limites de CI existantes restent inchangées.

- CI-R01 · S3 · Le moteur de tests PGlite 0.3.14 plante pendant le règlement fournisseur et provoque 12 échecs en cascade, selon son initialisation. Reproduit avec le point d’entrée standard sous Node 22 et 24. Mise à jour figée vers PGlite 0.4.6, toujours PostgreSQL 17 : les 21 tests comptables et les 7 tests de matrice passent sous Node 22. Aucun test ni contrôle de publication n’est retiré.
