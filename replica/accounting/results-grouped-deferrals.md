# Vérification des différés en mois complets et par lot

Référence fonctionnelle : Odoo 19.0 Enterprise, documentation officielle des charges et produits différés consultée le 27 octobre 2026. Ce lot correspond à H07 ; il ne démontre pas la parité globale de la comptabilité.

## Tests isolés du 27 octobre 2026

- 27 tests serveur réussis, zéro échec et zéro test ignoré : différés groupés, migration d'une base peuplée et régression des échéanciers existants. PostgreSQL embarqué PGLite ; la course entre deux sessions PostgreSQL 17 reste une validation CI distincte.
- Exemple indépendant : sources de 1 200 + 600 USD sur l'année et 600 USD commençant l'année suivante. Solde différé : 2 250 USD au 31 janvier, 2 100 USD au 28 février. Charges reconnues : 150 puis 300 USD. Chaque extourne restaure exactement les soldes avant la clôture suivante.
- Mois complets : premier mois commencé retenu ; dernier mois incomplet distinct exclu ; dernier mois entier inclus. Une source d'un centime ne devient jamais négative et conserve exactement son montant.
- Contrôles : période verrouillée, compte désactivé, aperçu périmé, double période, double requête, capacité source, contrepassations traçables, refus de validation générique, refus anonyme et approbation humaine obligatoire. Une extourne future attend son échéance et les droits de l'approbateur sont revérifiés.
- Migration peuplée : empreintes identiques de sept tables historiques ; montants et échéancier individuel préservés ; la deuxième reconnaissance et l'automatisation déjà approuvée continuent après migration. Aucune revue créée automatiquement.
- 18 parcours navigateur réussis : neuf nouveaux parcours et neuf régressions des échéanciers, ES/FR/EN × 390/768/1440. Après ajout de la pagination et du contrôle de compte actif, les neuf nouveaux parcours ont été rejoués avec succès, dont une revue de 54 sources affichée par pages de 50. Aucun débordement général ni violation axe WCAG A/AA dans le panneau testé. Captures desktop/mobile françaises examinées.

## Publication et limites

Migration appliquée : `20261027193621_accounting_grouped_deferrals`, 29 792 octets, SHA-256 `e8c7d88a0dd2f3163187a3cdbc4c2451d82bd9b27fb90c26ab46735fa9e46f54`. SQL exact et métadonnées archivés sous `supabase/sql/applied/`. [Comparaison de production](grouped-deferrals-production-verification.json) : 38 tables inchangées, 58 écritures, 138 lignes, débit = crédit = 8 552,49 USD, zéro écriture déséquilibrée. Zéro revue et zéro lien créés par la migration ; aucun exemple injecté en production.

Les deux tables privées ont RLS, aucune lecture directe par les rôles API ; la façade publique est invocateur et refuse le rôle anonyme. Capture d'historique activée. La délégation conserve les extensions TMS et Workhub intervenues pendant ce lot. Deux avertissements de sécurité préexistants restent inchangés ; aucun nouvel avertissement.

Sauvegarde logique ciblée vérifiée : sept tables et cinq fonctions, 133 637 octets, SHA-256 `8b17c61a4d0883f3131eb304188a266b0664a8e6fe682fdae4c92b598e9808f0`. Elle ne remplace pas une restauration PITR complète. La première tentative SQL a été entièrement annulée par un garde de compatibilité après un ajout TMS ; la migration a ensuite été adaptée à une délégation des fonctions courantes, sans supprimer l'extension TMS. Ne pas restaurer aveuglément une ancienne fonction commune si un autre module l'a enrichie entre-temps.

Après intégration de TMS, 19 tests serveur supplémentaires réussis, dont migration peuplée et conservation de ses droits d'historique. La course PostgreSQL 17 a réussi au commit `498159c` (workflow `40565585429`) : une seule revue pour deux générations simultanées, une seule paire d'écritures pour deux validations identiques. Le scénario utilise juillet, après le verrouillage de mai produit par un autre scénario. Les gates CI du dernier commit et la publication de l'interface restent à terminer. La navigation authentifiée en production n'est pas attestée.

La création automatique des échéanciers depuis les dates des lignes de factures et ses paramètres par compte restent à développer, suivis séparément en H14. Les sources de ce lot sont les lignes comptables validées existantes, sélectionnées explicitement. Les écrans utilisent les composants Coco et l'historique existant ; aucune ressource graphique Odoo n'est intégrée.

Pour revenir sur un lot comptabilisé, utiliser son action d'annulation motivée dans des périodes ouvertes : conserver les pièces originales et leurs contre-écritures. En cas de retrait de l'interface, conserver le schéma additif et les liens historiques ; toute correction de schéma après application exige une nouvelle migration.
