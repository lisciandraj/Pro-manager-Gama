# Coco ERP — amélioration des parcours quotidiens

Audit et réalisation du 14 octobre 2026, sur le dépôt `lisciandraj/Pro-manager-Gama`.

- Base examinée : `0437e4b84da95d4be674f3ead7da403ea188752d`.
- Point de restauration distant : branche [`checkpoint/coco-ux-20261014`](https://github.com/lisciandraj/Pro-manager-Gama/tree/checkpoint/coco-ux-20261014), créée avant les modifications.
- Livraison : branche `codex/erp-ux-market-20261014`.
- [Aperçu privé interactif](https://coco-erp-ux-preview.lovely-shark-4505.chatgpt.site).
- [Captures avant/après](https://coco-erp-ux-preview.lovely-shark-4505.chatgpt.site/review.html).

## Périmètre observé

Le code source, les composants partagés et les écrans exécutés localement avec des données de test ont été examinés. L’accès au dépôt a été vérifié séparément de Base44. Aucun accès administratif à la base de production n’a été utilisé. Les modifications portent sur `src/`, les traductions, les tests et la documentation ; les fichiers de distribution ont été régénérés par la compilation prévue dans le dépôt.

Les captures et les mesures utilisent les mêmes données fictives avant et après. Elles ne constituent pas un audit des données ni des processus réels de l’entreprise. L’aperçu reprend le build de l’ERP avec des doubles de données en mémoire, une mention « Démonstration » et le blocage des connexions externes. Les données de démonstration sont réinitialisées au rechargement ; les parcours sans données montrent un état vide. Certaines écritures comptables ne sont pas disponibles dans cet aperçu.

## Comparaison documentaire du marché

Il s’agit de pratiques relevées dans les documentations officielles, pas de tests chronométrés des produits concurrents.

| Référence | Pratique utile | Application à Coco ERP |
| --- | --- | --- |
| [Microsoft Dynamics 365 Business Central — Role Centers](https://learn.microsoft.com/en-us/dynamics365/business-central/dev-itpro/developer/devenv-designing-role-centers) | Organiser l’espace selon le rôle et les tâches à accomplir | Priorités comptables ouvrant directement les listes concernées, selon les droits existants |
| [Business Central — personnalisation](https://learn.microsoft.com/en-us/dynamics365/business-central/ui-personalization-user) | Préserver les préférences de champs, colonnes et actions | Conservation du composant de colonnes et des préférences par compte ; options secondaires dépliables |
| [Odoo 19 — opérations avec codes-barres](https://www.odoo.com/documentation/19.0/applications/inventory_and_mrp/barcode/operations/receipts_deliveries.html) | Centrer la préparation sur l’opération, le produit et le scan | Conservation du parcours de préparation existant et vérification du transfert automatique vers le TMS |
| [ERPNext — Workspace](https://docs.frappe.io/erpnext/workspace) et [Frappe — List View](https://docs.frappe.io/framework/user/en/api/list) | Raccourcis de travail, recherche, filtres, pagination et actions de liste | Recherche visible, retour conservant le contexte, cartes mobiles et raccourcis comptables |

## Constats et réalisation

| Module | Constat dans le code et les écrans de test | Résultat |
| --- | --- | --- |
| Accueil et Dashboard | Fond neutre, tuiles blanches à contours bleus, favoris et retour au menu déjà présents | Identité et structure conservées ; vérification du contraste, du clavier et des dimensions demandées |
| Composants communs | Recherche de tableau occupant une ligne entière même lorsque la place permet un regroupement ; messages natifs de validation peu persistants | Barre plus compacte sur ordinateur ; erreurs traduites près des champs avec focus, indications accessibles et conservation des saisies |
| Ventes | Dates et commandes secondaires très présentes ; tableau de devis peu pratique sur téléphone ; retour depuis « À traiter » perdant le contexte | Recherche et création de devis prioritaires ; dates, modèles et vues enregistrées dans un panneau dépliable ; cartes mobiles avec libellés ; montants alignés et statuts libellés ; retour avec critères, page, défilement et focus |
| Stock / Préparation | Vue mobile du stock et cadre des photos déjà présents ; logique de scan et transfert existante | Composants communs harmonisés, parcours existants conservés et tests de préparation/transfert exécutés |
| TMS | Journée, carte locale, tournées et interface chauffeur déjà présentes | Barre partagée plus compacte ; vérification des listes, erreurs, départ, preuves de livraison et interface chauffeur sur données de test |
| Comptabilité | Compteurs d’échéances visibles mais accès demandant de réappliquer des filtres | Priorités en tête de synthèse : factures clients/fournisseurs échues et banque non rapprochée ; ouverture directe de la liste filtrée ; distinction entre zéro et donnée indisponible |

Les couleurs relevées dans l’application sont `#157F98`, `#10677D`, `#238FA4` et `#F87826`. Le logo `coco-gama-logo.jpg` et les tokens existants sont conservés. Les modifications n’ajoutent aucune migration, aucun changement de permission, d’intégration ou de calcul métier. Les identifiants de modules, les RPC et les clés de préférences existants restent compatibles.

Les onglets visibles du module Ventes, l’icône de « Prochaine action », les documents liés et les dates/auteurs d’étapes étaient déjà implémentés. Les tests du suivi des dossiers vérifient notamment que des dates de clôture ne sont pas inventées lorsque la lecture est interdite ou échoue.

## Mesures de parcours

Mesures effectuées par interactions Playwright sur Chromium, à 1 440 px, avec les mêmes jeux de données. Le point de départ indiqué est déjà ouvert. Le compteur relève les activations de boutons ; une sélection de filtre est signalée séparément.

| Parcours | Avant | Après |
| --- | --- | --- |
| À traiter → ouvrir un devis → revenir à À traiter | 3 clics | 2 clics |
| Liste des devis → ouvrir un devis → revenir à la liste | 2 clics | 2 clics, avec retour au focus et au défilement |
| Synthèse comptable → factures clients échues | 2 clics + 1 sélection de filtre | 1 clic |

Une ouverture de la liste des devis conserve un seul appel RPC de liste. Deux séries successives de dix ouvertures locales, après échauffement et arrêt des autres vérifications, ont donné une médiane de 30,6 ms avant et 31,9 ms après. Cet écart de 1,3 ms avec des RPC simulés ne permet pas de conclure sur les performances en production. Aucun nouveau service ou chargement de données n’est ajouté pour les raccourcis comptables. Les [mesures brutes](2026-10-14-ergonomie-mesures.json) conservent chaque échantillon et le comptage des clics.

## Vérifications exécutées

- 147 scénarios navigateur distincts validés après corrections, dans les suites Ventes, composants, colonnes, comptabilité, responsive, contraste, stock, TMS, chargement et suivi des dossiers. Une première passe a révélé un chevauchement de pied de fenêtre, corrigé ; les anciens tests visant un texte supprimé et l’ancienne couleur de fond ont été actualisés. Le test des modèles de devis suit leur nouvel emplacement dépliable.
- La suite `ux-workspace.spec.js` est ajoutée à la configuration responsive utilisée par la CI Chromium/WebKit. WebKit n’a pas été exécuté dans cet environnement local.
- Matrice de 360, 390, 768 et 1 440 px en français, espagnol et anglais sur l’accueil, le Dashboard, les devis, le stock, le TMS et la préparation. La comptabilité possède sa matrice équivalente. Contrôle de l’absence de débordement de page et de chevauchement des commandes visibles ; les zones de défilement internes prévues restent autorisées.
- Vue cartes des devis : libellés présents, boutons d’au moins 44 px, choix explicite Tableau/Tuiles conservé après rechargement. Colonnes, tri et préférences couverts par les tests existants.
- Navigation des onglets au clavier, restauration du focus au retour et focus visible sur l’action principale. Contraste calculé d’au moins 4,5:1 sur le titre des tuiles, le bouton principal de devis et le badge de statut testé ; ce contrôle ciblé ne constitue pas un audit WCAG exhaustif.
- Erreurs de champ dans les trois langues : message associé au champ, focus sur la première erreur, conservation de l’aide, absence de soumission invalide et conservation des valeurs après une erreur d’enregistrement simulée.
- Raccourcis comptables : filtres réellement envoyés aux lectures, droits commerciaux respectés, distinction entre compteur nul et indisponible.
- Compilation, contrôles de sources, dépendances auditées, typage, liens documentaires, reproductibilité des fichiers générés et vérification du catalogue des migrations réussis. Aucune migration n’a été appliquée à une base opérationnelle. Le contrôle de démarrage passe : 14 scripts sur un budget de 15, 265 293 octets gzip sur 850 000, et 294 904 octets CSS sur 300 000.
- La commande générale de validation n’a pas fourni de résultat de sortie final : sa session s’est arrêtée pendant les tests unitaires après les tests SRI Open API. Les 28 fichiers restants ont été exécutés séparément : 56 tests réussis, aucun échec. Les contrôles de génération et de démarrage ont ensuite été exécutés avec succès. La CI doit confirmer le résultat global dans une exécution complète.
- Les tests de données utilisent les fixtures locales du dépôt. Le scénario de préparation entièrement scannée et de transfert atomique vers le TMS est passé, avec contrôles de droits et de répétition de commande.

## Limites et suite

Les dimensions ont été simulées dans Chromium ; Safari/iOS, les téléphones physiques et les scanners de l’entreprise restent à essayer. Les parcours sur les volumes réels et avec les comptes opérationnels nécessitent un environnement de recette autorisé. La livraison est une branche de modification et un aperçu privé ; la version publique de l’ERP n’a pas été remplacée.

L’aperçu privé a été empaqueté et sa publication confirmée par le service d’hébergement. Son cadre de démonstration a fait l’objet de contrôles de syntaxe ; aucun contrôle navigateur distinct de ce cadre hébergé n’a été effectué. Les tests et captures de l’ERP lui-même sont ceux détaillés ci-dessus.
