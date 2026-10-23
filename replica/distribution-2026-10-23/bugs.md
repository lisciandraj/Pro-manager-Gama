# Défauts et limites

Aucun défaut du lot confirmé avant exécution CI. Les scénarios de réseau, unité modifiée et article désactivé disposent de tests négatifs.

Limite de l'environnement : le téléchargement Chromium local a renvoyé une archive invalide, puis l'environnement s'est arrêté. Les compilations/tests et captures seront réalisés en CI. Cette limite ne justifie aucune suppression de contrôle.

## B01 — S3 — Dépassement du budget CSS initial

Reproduction : build puis check:startup sur b46549c. Attendu : CSS initial ≤ 300000 octets. Observé : 301528. Preuve : job architecture 120542245086. Correctif : charger sales-catalog.css à l'ouverture via le chargeur existant ; budget conservé. Validation CI requise.

## B02 — S3 — Focus après Échap

Reproduit deux fois dans le job ventes 120542244911 : la fenêtre se ferme mais le bouton d'ouverture n'est pas focalisé. Le désactiver pendant le chargement faisait perdre le point de retour d'ArcUI. Correctif : réactiver et focaliser le bouton juste avant l'ouverture du dialogue. Test de clavier conservé.

## B03 — Conditionnement modifié / fixture

Le scénario de changement de facteur échouait : la fixture partageait ses objets d'unité avec la réponse déjà reçue, contrairement à JSON sur le réseau. La fixture renvoie désormais une copie. Le catalogue conserve aussi le facteur choisi séparément et le recontrôle à l'ajout, même si un objet produit ou une recherche est rafraîchi. Aucun changement silencieux de quantité accepté.
