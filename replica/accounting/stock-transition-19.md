# Stock : préparation de la transition Odoo 19

Audit du 27 octobre 2026, en lecture seule. **K02–K05 restent incomplets** : ce document décrit le diagnostic initial. L’implémentation du coût standard et de la revue périodique est suivie dans [stock19-closing.md](stock19-closing.md) ; sa publication doit être vérifiée séparément.

## Référence figée

Odoo **19.0 Enterprise**, avec `stock` / `stock_account` et Comptabilité complète. Sources officielles relues le 27 octobre : [valorisation comptable](https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/inventory_valuation.html) et [aide-mémoire](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/inventory/inventory_valuation/cheat_sheet.html). Ne pas remplacer cette référence par la documentation 20.0 ou master.

En 19.0, le sous-livre physique évolue aux mouvements. Le livre comptable suit les factures en méthode perpétuelle et les écritures de clôture en méthode périodique. Le rapport de valorisation rapproche valeur comptable et stock à une date choisie, puis produit un brouillon à valider. Les revues distinguent reçu non facturé, livré non facturé, facturé non reçu et facturé non livré, avec comptes et date d’extourne configurables. Les options de société peuvent être remplacées sur les catégories. Le coût standard, FIFO et AVCO sont distincts du choix périodique/perpétuel. La fréquence de clôture peut être manuelle, quotidienne ou mensuelle.

## État réel de Coco

Les contrôles sont reproductibles avec [verify-stock-transition.sql](verify-stock-transition.sql). Les agrégats sont dans [stock-transition-before.json](evidence/stock-transition-before.json).

| Constat | Quantité | Conséquence pour la reprise |
| --- | ---: | --- |
| Produits avec quantité positive sans `stock_cost_books` | 1 756 | Aucune valeur FIFO/AVCO validée ne peut être déduite de la simple quantité actuelle |
| Sous-livres, valorisations et sources comptabilisées de stock | 0 | Aucune automatisation de stock n’est active à convertir |
| Mouvements physiques | 1 923 | Conserver les identifiants et les liens vers les autres modules |
| Mouvements sans coût historique | 39 | Tous antérieurs au début du suivi des coûts, le 20 septembre 2026 |
| Parmi eux, sans référence ni emplacement | 13 | Source et localisation à documenter ; ne pas inférer un fournisseur ou une contrepartie |
| Factures clients / liens quantitatifs | 17 / 42 | Chaque facture possède au moins un lien de quantité ; cela ne prouve pas la totalité de l’appariement aux livraisons |
| Factures fournisseurs / lignes de contrôle | 6 / 7 | Chaque facture possède des lignes de contrôle ; granularité de réception à vérifier |

Les 39 coûts manquants concernent 3 mouvements d’inventaire, 6 réceptions d’achats, 9 livraisons, 8 mouvements associés aux commandes clients et 13 anciennes lignes sans source. Leurs dates précèdent toutes la mise en place du suivi des coûts. Le prix catalogue courant n’est pas une preuve du coût ancien.

Le moteur actuel `private.erp_cost_post` maintient FIFO/AVCO. `private.gama_stock_accounting_post` peut comptabiliser les mouvements si un produit a été explicitement configuré ; ce mécanisme n’est pas celui d’Odoo 19. Le reclassement fournisseur actuel utilise la commande et un compte de réception unique. Il faut conserver ces comportements pour les produits non migrés, puis introduire une politique de transition datée, sans produire deux écritures pour la même opération.

## Construction native prévue

Réutiliser contacts, produits, catégories, factures, contrôles d’achats, livraisons, retours et coûts existants. Ajouter une configuration de valorisation avec date d’effet et comptes explicites, des instantanés de revue reliés aux sources et un registre des clôtures/contrepassations. Les montants calculés restent décimaux côté PostgreSQL ; la date comptable est distincte de `created_at`.

Le serveur doit refuser la clôture si la couverture des produits est incomplète, si des quantités restent sans coût justifié, si les comptes ne sont pas configurés ou si la date est verrouillée. L’aperçu doit donner la cause et les pièces de chaque différence. L’approbation humaine reste distincte de la génération ; une proposition Agent Coco reste non exécutée. Un verrou société/période et une clé de demande liée au contenu protègent la génération concurrente. La révision de l’aperçu doit expirer si les sources changent.

La reprise initiale doit faire valider quantité, coût et date observés pour chaque produit ; les valeurs anciennes inconnues restent signalées. Aucun report arbitraire du stock actuel vers une période passée. Les comptes, méthodes et soldes initiaux ne sont pas choisis par ce document. Une sauvegarde complète et un exercice de restauration doivent précéder une conversion structurelle.

## Scénarios indépendants à implémenter

Les montants suivants sont des attentes de test à construire, pas des résultats observés dans Coco ou dans une instance Odoo autorisée.

| Cas isolé | Attente chiffrée |
| --- | --- |
| FIFO : réception 10 × 10 puis 10 × 20, sortie de 12 | Coût sorti 140 ; stock restant 160 |
| AVCO : mêmes entrées et sortie | Coût moyen 15 ; coût sorti 180 ; stock restant 120 |
| Réception de 8 à 12, facture de 5 à 12 | Stock physique 96 ; dette facturée 60 ; reçu non facturé 36, chaque valeur reliée aux quantités concernées |
| Facture de 5 à 12 avant réception | Aucun stock physique ; 60 facturés non reçus à présenter dans la revue dédiée |
| Même clôture demandée deux fois | Une seule pièce ; rejeu identique ou conflit explicite si le contenu diffère |
| Coût absent, source modifiée ou période verrouillée | Aucun brouillon partiellement généré ; anomalie explicite |

Compléter avec les quatre combinaisons périodique/perpétuel et continental/anglo-saxon, écarts de facture, devises, frais d’approche, inventaires, retours partiels, clôtures successives, extournes, concurrence et trois langues. Les règles insuffisamment documentées, notamment le détail de certaines valorisations de retours, restent à confronter à une instance Odoo autorisée.
