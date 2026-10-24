# Résultats au point de contrôle

Code de départ : `7dfa6b422dd7eeea5161be935c0dabfb273aeebc`. Lecture production : 58 écritures posted, débit = crédit = 8 552,49 USD ; 27 transactions rapprochées, 5 ignorées, 57 non rapprochées ; une période fermée.

La restauration isolée du schéma et les quinze cas serveur des plans ont réussi. Un premier `npm run validate` a réussi avec 540 tests passés, zéro échec et un test de concurrence sauté faute de PostgreSQL local. Les modifications ultérieures restent soumises aux contrôles ciblés et à la CI du commit livré.

Le téléchargement Chromium local renvoie une archive tronquée ; les parcours navigateur et les captures sont confiés au runner GitHub Actions. Aucun résultat navigateur n'est déduit des seuls tests serveur. Le test multi-session exige son service PostgreSQL dédié et ne compte pas un SKIP local comme une réussite.

Les résultats définitifs, migrations effectivement appliquées, soldes après migration et commit réellement publié seront consignés après la CI et les lectures de production.

Vérification ciblée après ajout du planificateur et du garde de source : 69 tests passés, zéro échec, zéro SKIP (plans, livres, banque, valorisation, avances et historique). Sources, types, liens de documentation et archives de migrations ont passé leurs contrôles.
