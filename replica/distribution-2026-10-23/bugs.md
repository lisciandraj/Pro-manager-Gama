# Défauts et limites

Aucun défaut du lot confirmé avant exécution CI. Les scénarios de réseau, unité modifiée et article désactivé disposent de tests négatifs.

Limite de l'environnement : le téléchargement Chromium local a renvoyé une archive invalide, puis l'environnement s'est arrêté. Les compilations/tests et captures seront réalisés en CI. Cette limite ne justifie aucune suppression de contrôle.

## B01 — S3 — Dépassement du budget CSS initial

Reproduction : build puis check:startup sur b46549c. Attendu : CSS initial ≤ 300000 octets. Observé : 301528. Preuve : job architecture 120542245086. Correctif : charger sales-catalog.css à l'ouverture via le chargeur existant ; budget conservé. Validation CI requise.
