# Résultats — formats bancaires

27 octobre 2026. Lot F04, parité toujours partielle.

- 26 tests ciblés réussis : 9 lecteurs/identités/décodage, 8 CSV, 2 worker Excel, 7 base de données (6 scénarios et leur suite). Aucun échec ni test ignoré.
- 11 parcours navigateur réussis sur le code final : OFX espagnol, CAMT français et CODA anglais à 390/768/1440 px, QIF mobile et XLSX tablette. Base PGLite isolée et RPC réels ; aperçu accessible, écriture équilibrée, réimport sans doublon, liens aux pièces. Contrôles ajoutés pour masquer les champs inapplicables et traduire l'action de confirmation.
- 20 parcours import/écriture et 20 parcours configuration CSV/formats réussis lors des régressions locales. La CI doit confirmer le dernier commit et la concurrence de deux sessions PostgreSQL 17.
- Build, syntaxe, types, reproduction des fichiers générés, documentation, manifeste SQL et budget de démarrage réussis. La nouvelle feuille de styles est chargée avec le module comptable, sans élargir les ressources initiales.

Les captures locales ont été inspectées ; aucune donnée réelle n'est utilisée. Aucun import de test n'est effectué en production.

Migration, contrôles de soldes avant/après et publication : en attente des contrôles CI. Le résultat connecté en production reste à vérifier avec un accès autorisé. Le pourcentage pondéré Replica est un diagnostic, pas une attestation d'équivalence. Voir [les variantes restantes](bank-formats.md) et [la matrice](features.csv).
