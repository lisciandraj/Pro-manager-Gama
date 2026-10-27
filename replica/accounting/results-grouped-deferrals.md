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

La migration n'est pas encore appliquée en production. Avant bascule : conserver les définitions remplacées et les données concernées, comparer les empreintes, exécuter les gates CI et archiver le SQL exact appliqué. Aucun exemple chiffré n'est injecté dans la base réelle.

La création automatique des échéanciers depuis les dates des lignes de factures et ses paramètres par compte restent à développer, suivis séparément en H14. Les sources de ce lot sont les lignes comptables validées existantes, sélectionnées explicitement. Les écrans utilisent les composants Coco et l'historique existant ; aucune ressource graphique Odoo n'est intégrée.

Pour revenir sur un lot comptabilisé, utiliser son action d'annulation motivée dans des périodes ouvertes : conserver les pièces originales et leurs contre-écritures. En cas de retrait de l'interface, conserver le schéma additif et les liens historiques ; toute correction de schéma après application exige une nouvelle migration.
