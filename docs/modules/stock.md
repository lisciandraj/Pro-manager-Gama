# Stock : existences et opérations

Le module public reste `warehouses`, avec les points d’entrée compatibles `GamaOpenWarehouses` et `GamaInventoryV2`. `gama-inventory-v2.js` est une intégration légère ; `gama-stock-workspace.js` est téléchargé à la première ouverture. Les nouvelles vues chargent ensuite `gama-stock-operations.js`.

Les existences lisent uniquement les produits sans photos, les entrepôts, les emplacements et les quantités avant leur premier affichage. Le snapshot serveur enrichit ensuite les quantités disponibles et entrantes. Les règles de réapprovisionnement, fournisseurs, inventaires et étagères sont chargés lorsque leur onglet est ouvert. Les lectures simultanées sont partagées ; un échec peut être réessayé. Les résultats d’une ancienne session ne sont pas réutilisés. Les quantités affichent jusqu’à trois décimales.

## Por tratar

Cette vue rassemble la disponibilité nulle ou inférieure au minimum, les achats envoyés/partiels avec reliquat et date prévue dépassée, les ajustements en attente et les inventaires arrivés à échéance. Les boutons ouvrent le produit, la commande, la demande d’ajustement ou l’inventaire correspondant. Les informations d’Achats restent réservées aux profils qui peuvent lire ce module ; les ajustements et recensements restent réservés aux administrateurs et magasiniers.

## Reabastecimiento

`gama_stock_insights('reabastecimiento')` retourne des propositions actuelles. Seuls les produits physiques actifs et non exclus de réapprovisionnement sont proposés.

- La moyenne quotidienne pondère les sorties des 30/60/90 derniers jours à 50/30/20 %. Les mouvements retenus sont les livraisons, sorties manuelles et consommations de production, ainsi que les anciennes sorties sans type. Les transferts, ajustements et retours sont exclus.
- Le délai provient des règles de réapprovisionnement ; sans délai défini, la proposition indique explicitement l’estimation de 7 jours. Une règle globale est prioritaire ; à défaut, les règles d’entrepôts sont regroupées.
- Avec une demande récente, le minimum couvre le délai et 50 % de sécurité ; l’objectif ajoute 14 jours de couverture. Les seuils configurés restent des planchers. Sans demande récente, seuls les seuils configurés sont utilisés.
- Le besoin tient compte du physique moins les réservations, des achats envoyés/partiels restants et des brouillons existants. La quantité respecte le minimum de commande et le multiple de conditionnement, à trois décimales.

L’utilisateur sélectionne les propositions avec un fournisseur actif. `gama_stock_replenish` revalide les quantités et fournisseurs, puis crée un brouillon par fournisseur dans **une transaction** avec `gama_purchase_save`. Une proposition périmée annule l’ensemble et demande une actualisation. Une clé stable et un reçu serveur permettent de réessayer une requête réseau sans dupliquer les commandes. Les propositions concurrentes de ce flux sont sérialisées. Aucun envoi au fournisseur, mouvement de stock ou réservation n’est effectué. Les commandes se vérifient et s’envoient depuis Achats. La limite existante est 500 lignes par fournisseur et 3 000 produits sélectionnés par opération.

## Stock sin rotación

Les filtres 30/60/90 jours affichent les produits avec stock physique positif, la date de dernière sortie retenue, les unités et le capital immobilisé au prix d’achat actuel. Sans sortie enregistrée, l’ancienneté commence à la création du produit, ce qui est indiqué dans la colonne. Un transfert ou un ajustement ne constitue pas une vente et ne remet pas ce délai à zéro.

## Inventaires cíclicos

Le contrat existant `gama_count_create` accepte désormais `assigned_to`, `due_date`, `priority`, `product_id` et `repeat_of`. Le responsable doit être un administrateur ou magasinier actif. La sélection d’un produit limite les lignes de comptage à ce produit dans l’entrepôt et l’emplacement/catégorie choisis.

Les rappels montrent les inventaires ouverts dont la date limite est atteinte et les cycles validés dont `next_due` est atteint sans recensement suivant. « Preparar siguiente » reprend le périmètre, le responsable et le cycle dans le formulaire. Un seul inventaire suivant non annulé peut être lié à un cycle précédent.

La priorité A rassemble les produits qui concentrent les premiers 80 % du capital stocké ; B correspond aux 15 % suivants. Les écarts récurrents comptent les inventaires validés avec différence des 180 derniers jours. Ces signaux permettent de préparer un recensement ciblé prioritaire. Le comptage aveugle, le second compteur, les autorisations de validation et les contrôles de stock périmé sont conservés. Seule la validation du comptage ajuste les existences.

## Accès et validation

Les API publiques sont `SECURITY INVOKER` et délèguent à des fonctions privées contrôlant Auth, MFA, rôle et activation du module. L’agrégateur interne n’est pas exécutable par les clients. Les droits du cache Coco Intelligence restent inchangés. Les nouveaux champs et index sont ajoutés par `20261004191646_stock_workspace_improvements.sql`.

Les règles sont testées par restauration complète dans PGlite avec des données isolées (`tests/stock-workspace-db.test.cjs`). Les parcours, chargements différés, reprises et affichages mobiles sont testés avec un transport mémoire dans `tests/stock-workspace.spec.js`, en complément des tests Stock et inventaires existants.
