# Ventes : devis, commandes, factures et encaissements

État du 13 octobre 2026. La carte **Ventes** ouvre les documents autorisés. Le sélecteur présente cinq sections, selon les droits : **À traiter**, **Devis et commandes**, **Factures et encaissements**, **Conditions commerciales**, **Pilotage**. Les anciennes adresses `quotes`, `customer-requests`, `sales-orders`, `payments`, `price-lists` et `matrix` restent compatibles. Le magasinier entre par Ventes dans les commandes et conserve ses seules actions logistiques.

## Parcours

1. **À traiter** réunit les demandes sans devis, les devis ouverts, les commandes à terminer et les échéances proches ou dépassées. Les listes sont paginées. La sélection de commandes livrées permet de créer une facture groupée pour un même client.
2. **Devis et commandes** conserve les demandes, devis et commandes dans des onglets. Les devis se filtrent par référence/client, état, dates, propriétaire, relance et expiration. Une vue peut être enregistrée par utilisateur sur son appareil.
3. Le devis préremplit l'entreprise et le client. Adresse de livraison et conditions essentielles restent visibles ; les autres détails se déplient. Les lignes se modifient dans une grille, avec unités de vente, quantités, prix hors taxes, remise et TVA. Les changements de quantité, client ou date recalculent le tarif commun `gama_resolve_price` utilisé aussi par le catalogue public. Une réponse de prix devenue ancienne ne remplace pas les valeurs courantes.
4. Les conditionnements utilisent `product_units.factor`. Quantité de vente × facteur = quantité de stock. Le serveur vérifie le produit, l'unité active et cette conversion. Les lignes conservent le libellé et le facteur historiques ; le stock reste géré dans l'unité de base.
5. Les commandes directes proposent le même tarif par client et quantité. Un prix manuel exige un motif. La confirmation réserve les quantités disponibles, sans sortie de stock. La préparation, l'emballage, l'expédition et les preuves restent dans le dossier existant ; voir [Préparation et retours](fulfillment.md).
6. Le dossier de commande montre séparément l'expédition, la livraison signée ou la prestation réalisée, la facturation et le paiement. Une vente est terminée lorsque toutes les quantités sont livrées et facturées et toutes les factures actives sont soldées. L'état fiscal reste distinct.
7. Une facture interne peut porter sur tout ou partie des quantités **livrées et non encore facturées**. Une livraison physique doit être marquée livrée et avoir une signature ; un service exige une réalisation enregistrée. La facture conserve les prix de commande, le client, l'entreprise et les documents sources dans un instantané. Elle ne crée aucun mouvement de stock.
8. Plusieurs commandes confirmées du même client peuvent alimenter une facture unique. Les quantités restent rattachées à leurs lignes ; la facture apparaît dans chaque dossier source. Le chiffre d'affaires et le coût sont répartis par commande pour la rentabilité. L'encaissement porte sur la facture unique.

## Conditions et modèles

Dans **Conditions commerciales**, les tarifs et la matrice restent disponibles. L'administrateur configure une remise maximale et une marge minimale estimée, ainsi que le mode de facturation par client : automatique à chaque livraison, manuel ou groupé. Un seuil vide est désactivé ; aucun seuil imposé n'est ajouté aux comptes existants. La marge du devis utilise le coût d'achat courant ; celle d'une commande utilise ses coûts historiques lorsqu'ils sont disponibles. Un coût manquant avec seuil de marge actif demande une validation.

Une exception commerciale demande une approbation administrateur avant l'envoi/l'acceptation du devis ou la confirmation de la commande directe. La validation est liée à l'empreinte du document : changer ses conditions l'invalide. Demande, approbation et motif sont inscrits dans le journal du document.

Le dossier permet de **copier une vente** et d'enregistrer un **modèle de devis**. Leur réutilisation crée un nouveau brouillon et recalcule les prix courants. Les documents acceptés restent figés. Les propositions récurrentes existantes sont accessibles dans Pilotage et depuis les commandes ; elles gardent leur confirmation client obligatoire.

## Facturation et fiscalité

Le mode automatique crée une facture pour les nouvelles quantités livrées lors de la signature ou de la réalisation d'un service. Les modes manuel/groupé attendent l'action du commercial. Une clé stable empêche qu'un rechargement ou une modification de preuve crée une deuxième facture. Les montants sont conservés dans `external_invoices`, le registre financier existant ; ajouter une référence externe ne crée pas un second montant.

La facture interne n'a pas de valeur fiscale. L'émission, le suivi et les éventuelles annulations SRI utilisent le module fiscal existant. Annuler un enregistrement financier ne remet pas les marchandises en stock : utiliser le retour. Les factures annulées/rejetées et leurs lignes restent dans l'historique. Les montants/quantités déjà couverts par une facture active ne peuvent être facturés une deuxième fois. Les factures externes historiques restent liées à un seul dossier.

## Sécurité et chargement

`public.gama_sales_workspace` est une façade invoker. Son implémentation privée vérifie la session, MFA, le profil actif, les modules et actions autorisés. Les paramètres, modèles, approbations et allocations sont des tables privées avec RLS et sans accès direct PostgREST. Les magasiniers voient les quantités logistiques, sans factures, montants facturés ou encaissements ; aucune entrée anonyme n'est ajoutée.

Les factures utilisent la transaction et le verrou commun des ventes, un ordre de verrouillage stable et une clé UUID liée à l'acteur et au contenu. Les quantités sont vérifiées sous verrou contre les preuves et factures courantes. Les fichiers et signatures sont chargés à la demande.

Les éditeurs et outils des ventes sont chargés à leur ouverture, avec recherche produits/clients limitée à 30 résultats et conservation de la sélection. La liste des devis ne transfère ni lignes ni instantané accepté. Les plafonds de démarrage restent ceux de `config/performance-budget.json`.

## Installation et vérification

Migration additive : `supabase/migrations/20261013191210_sales_workspace.sql`, après les migrations existantes, avant le frontend. Elle ne crée aucune facture métier et ne réécrit aucun document historique. L'installation conserve son modèle d'une seule entreprise.

Les tests `tests/sales-workspace-db.test.cjs` restaurent toutes les migrations dans PostgreSQL isolé et vérifient tarifs/unités, livraison signée, quantités partielles, idempotence, regroupement/rentabilité, approbations et droits. `tests/sales-workspace.spec.js`, `tests/sales-module-tabs.spec.js`, `tests/quote-adjust.spec.js`, `tests/sales-orders.spec.js` et `tests/internal-invoices.spec.js` vérifient les parcours de l'interface, les traductions et le mobile. Les tests de stock, services, fiscalité, paiements et architecture existants restent requis.
