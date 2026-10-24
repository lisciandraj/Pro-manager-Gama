# Résultats au point de contrôle

Code de départ : `7dfa6b422dd7eeea5161be935c0dabfb273aeebc`. Lecture production : 58 écritures posted, débit = crédit = 8 552,49 USD ; 27 transactions rapprochées, 5 ignorées, 57 non rapprochées ; une période fermée.

La restauration isolée du schéma et les quinze cas serveur des plans ont réussi. Un premier `npm run validate` a réussi avec 540 tests passés, zéro échec et un test de concurrence sauté faute de PostgreSQL local. Les modifications ultérieures restent soumises aux contrôles ciblés et à la CI du commit livré.

Le téléchargement Chromium local renvoie une archive tronquée ; les parcours navigateur et les captures sont confiés au runner GitHub Actions. Aucun résultat navigateur n'est déduit des seuls tests serveur. Le test multi-session exige son service PostgreSQL dédié et ne compte pas un SKIP local comme une réussite.

Les résultats définitifs, migrations effectivement appliquées, soldes après migration et commit réellement publié seront consignés après la CI et les lectures de production.

Vérification ciblée après ajout du planificateur et du garde de source : 69 tests passés, zéro échec, zéro SKIP (plans, livres, banque, valorisation, avances et historique). Sources, types, liens de documentation et archives de migrations ont passé leurs contrôles.


CI du commit `d83808672bdf71628f7ba2443f965362b86233e1` : [échéanciers natifs](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40106958977), 61 parcours navigateur réussis et test PostgreSQL 17 à deux sessions réussi. Les neuf scénarios d'échéancier contrôlent trois langues et trois largeurs, avec axe sur le formulaire et le détail. Les captures ont été examinées ; une première disposition trop haute sur téléphone a été corrigée, puis vérifiée à nouveau. Les tests généraux de la base sur la version intégrée précédente ont compté 549 réussites, zéro échec et deux SKIP de services dédiés ; les jobs de concurrence exécutent ces cas avec leurs services.

Polissage complémentaire en attente de CI : classe primaire Coco pour les actions principales, exclusion du tableau de saisie des outils de consultation, lien depuis l'historique réel vers l'échéancier. La migration de production n'est pas encore appliquée à ce point de contrôle.
