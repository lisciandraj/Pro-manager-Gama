# Reprise et retour arrière

1. Inventorier les pièces et associations avec les contrôles existants (sans `sync` dans un script de lecture). Conserver les totaux avant/après dans `results.md`.
2. Tester la restauration complète des migrations dans PGlite, puis les scénarios comptables isolés. Les tests n'utilisent aucun identifiant réel ni le serveur de production.
3. Appliquer la migration additive `20261024155142_accounting_plans.sql` uniquement après réussite. Aucune reprise des 58 écritures ni compensation d'écart ; aucun plan de production n'est créé pour tester.
4. Vérifier les définitions des façades, ACL, triggers, RLS et le registre de migrations. Comparer nombre d'écritures, débit, crédit, banques et périodes à l'inventaire initial.
5. Conserver le commit précédent pour un retour de l'interface. La base additive peut rester en place sans usage. Avant suppression d'une table de plans, arrêter ses utilisateurs et exporter plans/occurrences/commandes ; si des écritures existent, conserver les tables et corriger par contre-écritures. Ne jamais supprimer les écritures issues de plans utilisés.

La sauvegarde physique/PITR du projet et un exercice réel de restauration ne sont pas encore attestés. La migration additive évite une bascule destructive ; elle ne constitue pas une preuve de sauvegarde. Les opérations futures de conversion du stock, multi-sociétés ou reprise massive nécessitent cette preuve et une comparaison détaillée des soldes.

Sauvegarde logique ciblée réalisée avant migration : 58 écritures, 138 lignes, 89 transactions bancaires, comptes/journaux et deux périodes. Empreinte SHA-256 : `2bef42f16df30ab0918449fb4f9cd96360defafd0d467fe23c1d4caa1cc744e3` (378 144 octets). Les données privées sont conservées séparément du dépôt public. Cette sauvegarde ciblée ne remplace pas une sauvegarde intégrale du projet.
