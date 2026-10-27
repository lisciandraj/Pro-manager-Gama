# Résultats — formats bancaires

27 octobre 2026. Lot F04, parité toujours partielle.

- 26 tests ciblés réussis : 9 lecteurs/identités/décodage, 8 CSV, 2 worker Excel, 7 base de données (6 scénarios et leur suite). Aucun échec ni test ignoré.
- 11 parcours navigateur réussis sur le code final : OFX espagnol, CAMT français et CODA anglais à 390/768/1440 px, QIF mobile et XLSX tablette. Base PGLite isolée et RPC réels ; aperçu accessible, écriture équilibrée, réimport sans doublon, liens aux pièces. Contrôles ajoutés pour masquer les champs inapplicables et traduire l'action de confirmation.
- 20 parcours import/écriture et 20 parcours configuration CSV/formats réussis lors des régressions locales. La CI doit confirmer le dernier commit et la concurrence de deux sessions PostgreSQL 17.
- Build, syntaxe, types, reproduction des fichiers générés, documentation, manifeste SQL et budget de démarrage réussis. La nouvelle feuille de styles est chargée avec le module comptable, sans élargir les ressources initiales.

Les captures locales ont été inspectées ; aucune donnée réelle n'est utilisée. Aucun import de test n'est effectué en production.

Migration additive 20261027183731 appliquée et archivée exactement (9 835 octets, SHA256 9476eb8e02d9b72793df9904769e463889bab9a9380511208c123ce1f883fede). Les empreintes des 30 tables contrôlées sont inchangées : 58 pièces, 138 lignes, débit/crédit 8 552,49 USD, aucune écriture déséquilibrée. Aucune provenance ni opération de test créée. RLS, RPC invoker, refus anonyme, absence d’accès direct et capture d’historique vérifiés. Les deux avertissements de sécurité préexistants sont conservés, sans nouvelle alerte. Sauvegarde ciblée : 8 tables et 3 fonctions, 181 398 octets, SHA256 43250aa633968900b83eadb15e602f80632a99a483feab47b307234237a68997. Voir bank-formats-production-verification.json. Publication web en attente des contrôles CI. Le résultat connecté en production reste à vérifier avec un accès autorisé. Le pourcentage pondéré Replica est un diagnostic, pas une attestation d'équivalence. Voir [les variantes restantes](bank-formats.md) et [la matrice](features.csv).
