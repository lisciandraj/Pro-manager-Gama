# Livraison du dossier commercial Coco ERP — 15 octobre 2026

## Environnements et sauvegarde

Dépôt : `lisciandraj/Pro-manager-Gama`. Référence avant intervention : `9b3e988bae73005c243f66707ca18e77c8eef8e7`, conservée par la branche distante `restore/sales-before-2026-10-15`. ERP : `https://lisciandraj.github.io/Pro-manager-Gama/`. Portail : `https://gama-coco.pages.dev/`. Supabase : `mknsaibrewksgomuslev`.

Une archive privée `Coco_ERP_Restauration_Ventes_2026-10-15.zip` contient le snapshot commercial cohérent du 15 octobre à 18:31 UTC : 29 tables, notamment 41 devis, 508 lignes de devis, 27 commandes, 28 lignes de commande et 16 factures. Elle contient aussi les définitions/ACL des fonctions avant intervention, les règles tarifaires et le script de retour serveur. Le manifeste contient les SHA-256 de chaque fichier ; l'archive a été rouverte et contrôlée. Les médias Storage, identités Auth et données des autres modules ne sont pas modifiés par cette livraison et ne sont pas inclus dans cet export ciblé. Les données métier de sauvegarde ne doivent pas être poussées dans le dépôt public.

## Fichiers principaux

| Fonction | Sources |
| --- | --- |
| Identité commune, états, activités, confidentialité | `supabase/migrations/20261015183402_sales_dossier_lifecycle.sql` |
| Acomptes et déduction comptable | `supabase/migrations/20261015183712_sales_billing_and_deposits.sql` |
| Liste à facturer, analyse, portail et protection SRI | `supabase/migrations/20261015183918_sales_dossier_views_and_portal.sql` |
| Conditions figées et moteur tarifaire commun | `supabase/migrations/20261015185009_sales_terms_and_pricing_rules.sql` |
| Crédit, dérogation et répétitions de requêtes | `supabase/migrations/20261015185300_sales_transition_integrity.sql` |
| Interface et navigation | `src/features/sales/dossier.js`, `quotes.js`, `editor.js`, `order-design.js`, `src/features/finance/pricing.js` |
| Portail et traductions | `src/storefront/b2b.js`, `b2b.css`, `locales/catalog.tsv` |
| Chargement/compilation | `config/runtime-assets.json`, `src/core/lazy-modules.js`, sorties générées par `npm run build` |
| Régressions | `tests/sales-dossier-db.test.cjs`, `sales-concurrency.test.cjs`, `sales-dossier.spec.js` et suites existantes adaptées |

Fonctions d'entrée : `gama_sales_dossier`, `gama_sales_workspace`, `gama_quote_action`, `gama_price_book_action`, `gama_b2b_action` et `gama_sri_prepare`. Les noms publics existants restent compatibles ; les adaptations comptables restent privées.

## Retour arrière

1. Suspendre temporairement les nouvelles opérations commerciales pendant le retour ; conserver un snapshot des changements depuis le déploiement. Ne pas écraser les transactions récentes par l'ancien export.
2. Pour revenir à l'interface précédente, republier l'artefact compilé de la branche `restore/sales-before-2026-10-15` via le workflow Pages, puis vérifier `coco-build.json`. Les migrations sont compatibles avec les anciennes adresses. Conserver les tables additives et l'historique. Sur Cloudflare, sélectionner le dernier déploiement de production antérieur `fcd6a0b1-99d7-4717-9c95-dbf8b16fa924` par l'opération de rollback Pages.
3. Pour un retour serveur complet avant utilisation des nouvelles fonctions : extraire l'archive privée, vérifier le manifeste, exécuter `node scripts/prepare-sales-rollback.cjs <répertoire extrait> <rollback.sql>`, puis appliquer ce SQL transactionnel via un accès administrateur Supabase. Le script restaure les définitions/ACL capturées, retire l'accès au nouveau RPC et conserve les structures et données additives.
4. Le script refuse de restaurer l'ancien moteur si acomptes, facturation sur commandé, formules/catégories, options, activités ou acceptations portail ont été utilisés. Dans ce cas conserver les fonctions compatibles, corriger en avant et traiter les pièces comptables avec leur processus d'annulation/avoir. Ne pas supprimer ces pièces ni leur historique.
5. Vérifier les droits, références, totaux, réservations, factures et paiements après restauration. Aucune restauration automatique de lignes métier n'est déclenchée : le snapshot ciblé sert à comparer ou restaurer sélectivement après contrôle des transactions postérieures.

Le SQL généré a été exécuté dans une reconstruction PostgreSQL isolée pour vérifier sa syntaxe, ses restaurations et la révocation du nouveau RPC. Ne pas supprimer les entrées du journal des migrations : les migrations additives restent historiquement appliquées.

## Parcours de vérification

Dans un environnement de test : **Ventes → Devis → Nouveau**, choisir un client, ajouter plusieurs produits, une section et une option. Vérifier le tarif expliqué et conserver un prix manuel avec motif. Enregistrer, finaliser le document et préparer l'email : l'email n'est pas annoncé envoyé. Confirmer un accord téléphonique avec sa référence ; le UUID de dossier et la référence devis restent identiques. Vérifier le blocage crédit ou une dérogation administrateur motivée.

Ouvrir la commande puis **Préparations et colis**. Scanner et valider toutes les quantités requises : le colis complet rejoint automatiquement TMS, sans bouton de transmission ni fermeture manuelle. Planifier/expédier dans TMS, puis enregistrer la réception réelle et sa preuve. Une livraison partielle reste dans la même commande.

Revenir dans **À facturer** : sur livré, facturer seulement la réception prouvée ; sur commandé, les quantités deviennent éligibles après confirmation. Vérifier 20 × 50 USD HT, 12 livrés → 600 HT, puis 8 → 400 HT. En cas d'acompte configuré, vérifier la déduction unique sur les factures finales. Comptabiliser dans Comptabilité, enregistrer un règlement partiel puis le solde dans le module existant ; rapprocher sans créer un nouveau paiement. Les quatre états du dossier évoluent indépendamment. Utiliser Retours/Avoirs pour corriger une exécution partielle.

## Paramètres et limites

À configurer : politique produit/défaut, compte de passif pour acomptes, seuils et routes logistiques existants, fiscalité et connecteur SRI existant. Le mapping fiscal des acomptes exige une validation du fournisseur avant déblocage ; l'interface n'annonce aucune autorisation SRI fictive.

L'acceptation portail enregistre l'accord et attend la confirmation interne. Signature électronique, paiement en ligne et coupons/fidélité ne sont pas activés sans infrastructure opérationnelle. Aucun second moteur promotionnel n'est créé. La société et la devise comptable restent celles de l'installation ; aucune conversion FX automatique ni nouvelle gestion multi-société n'est introduite. Les équipes/variantes absentes du modèle existant ne sont pas inventées. La saisie d'options s'effectue dans l'éditeur interne ; le portail consulte l'offre et accepte l'ensemble, sans configurateur d'options en ligne.

Les tests ne déclenchent aucun email client, paiement externe ni émission fiscale réelle. Le contrôle du site publié vérifie le build et les ressources servies ; il ne constitue pas un test transactionnel avec les données clients de production.

## Preuves de validation et publication

Cette section est complétée avec les identifiants de version et les résultats vérifiés après le déploiement. Ne pas assimiler une branche ou une compilation locale à une publication en production.
