# Défauts reproduits et corrigés

B01 · S3 · En ouvrant un canal, le shell Coco conserve son titre H1 et masque la
seconde en-tête commune. Le premier titre visible de la zone de travail était
H3. Résultat attendu : H2 puis H3 ; obtenu : H1 puis H3. Correction : titre de vue
H2, sous-sections H3. Vérification : analyse axe ordinateur et téléphone réussie.

Aucun S1 ou S2 restant ouvert dans les parcours testés. Les capacités non réalisées
restent dans la matrice de parité, et ne sont pas présentées comme des défauts
corrigés. Voir build-log.md pour les contrôles et les références de livraison.

B02 · S1 · L’extension du résolveur d’historique avait réintroduit une ancienne
politique, sans le filtrage complémentaire des synthèses RH et des propositions.
Le contrôle de régression RH l’a reproduit. La migration corrective conserve
intégralement la politique courante et le résolveur du nouvel espace. Les 20
contrôles ciblés des historiques, propositions et canaux passent. La correction
est installée et son expression vérifiée avant publication de l’interface.
