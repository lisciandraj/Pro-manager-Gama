# Coco ERP — Recon visuelle Odoo

Date : 15 octobre 2026. Base : `e03de7b` de `lisciandraj/Pro-manager-Gama`.
Skills appliqués : Replica Recon, Design et Test. Il s’agit d’améliorer l’ERP existant à partir des captures déjà réunies, pas de reconstruire Odoo ni d’en reproduire toutes les fonctions.

## Périmètre et preuves

Le catalogue de recherche couvre 31 rubriques Coco et 44 images officielles Odoo. Les correspondances visuelles principales de cette passe figurent ci-dessous ; les autres modules bénéficient des composants communs. Les captures montrent des dispositions, mais ne permettent pas de déduire le comportement d’un bouton ou les contrats de données d’Odoo. Les interactions implémentées viennent du code et des tests de Coco.

| Écran Coco | Référence consultée | Observation et adaptation |
| --- | --- | --- |
| Produits | Fiche produit Odoo 19 | Champs groupés, liste comme point d’entrée, accès explicite au formulaire. Catalogue placé avant le formulaire existant. |
| Ventes | Liste des devis Odoo 19 | Commandes compactes au-dessus des données. En-tête et espacements harmonisés, cinq sections de navigation conservées. |
| CRM / Opportunités | Capture officielle CRM | Colonnes par étape et cartes avec hiérarchie titre/client/montant. Cartes et contrôles d’étape plus lisibles. |
| Documents | Capture officielle Documents | Filtres latéraux séparés des résultats. Recherche dans la zone de résultats ; filtres empilés sur téléphone. |
| Base de connaissances | Capture officielle Knowledge | Arborescence à gauche et surface de lecture continue. Rail et article réunis, largeur et interligne de lecture réglés. |
| Formulaires et autres modules | Motifs communs des références | Un en-tête, des actions regroupées, champs délimités, focus visible et pied de formulaire accessible. |

Les URLs et empreintes sont dans `screens/sources.json`. Les couleurs, illustrations et noms affichés restent ceux de Coco.

## Parcours et états à préserver

- Produits : catalogue → modifier → formulaire prérempli → valider ; créer ouvre un brouillon vide. Les identifiants, contrôles d’unicité, prix et gestion du stock ne changent pas.
- Ventes : recherche/filtres → devis/commande → retour avec position et focus conservés. Les cinq sections restent visibles ; les outils administratifs rejoignent l’en-tête.
- CRM : pipeline → fiche → changement d’étape ; gagné/perdu et erreur réseau conservent leurs règles et possibilités de reprise.
- Documents : statut/catégorie/employé/origine + recherche → liste paginée → détail → fichier/version → archivage/restauration. La recherche commune doit rester dans le panneau des résultats lors de son montage.
- Connaissances : recherche/arbre → article → modification/sous-article → sauvegarde, avec brouillon conservé en cas d’erreur.
- Composants : vide, chargement, erreurs, désactivé, focus clavier, sélection de ligne, vue tableau/tuiles, traductions FR/ES/EN et largeur 320–1440 px.

## Contraintes existantes

Logo original, Favoris, tuiles d’accueil blanches bordées de bleu, navigation blanche et palette pétrole/orange conservés. Quadrillage des tableaux et préférences par compte conservés. Les variantes mobiles déjà prévues pour Stock, Devis et À traiter restent prioritaires en l’absence de préférence personnelle. Le Dashboard garde ses quatre indicateurs, la commande ses huit étapes, et le SRI ses contrôles effectifs. Aucun changement d’API, de table, de permission, de synchronisation ou de stockage local.

## Composants et données observés dans Coco

`ArcUI` fournit boutons, champs, panneaux, en-têtes, tableaux, badges, pagination et dialogues. `GamaTable` monte recherche, tri, colonnes et vue ; il déplace les champs existants pour conserver leur gestionnaire. `src/ui/controls.js` monte les outils selon les droits. Les styles spécifiques se superposent aux tokens communs.

Les données existantes sont `products`, `invoices`/lignes, `crm_pipeline_stages`/`crm_opportunities`, `business_documents`/fichiers et `knowledge_articles`. Ce relevé décrit le code existant ; aucune migration ni nouveau modèle n’est nécessaire pour cette intervention visuelle.

## Limites

La conformité fonctionnelle complète avec Odoo n’est pas un objectif. Les accès de production, achats, données fiscales et paiements réels ne sont pas utilisés comme fixtures. Les contrôles automatiques et captures de cette passe utilisent les mocks du dépôt.
