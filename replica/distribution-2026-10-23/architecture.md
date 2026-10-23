# Architecture du lot catalogue

Reprend [recon](recon.md) et [matrice](features.csv). Stack inchangée : JavaScript/Vite, ArcUI, RPC Supabase/PostgreSQL. Zéro table, zéro migration, zéro nouvel endpoint.

## Intégration

- sales/catalog.js → coco-sales-catalog.js, différé via le manifeste existant. ArcUI.dialog assure focus, retour et protection contre doubles soumissions.
- editor.js transmet client/date, identité du formulaire/session, produits déjà présents et callback d'ajout atomique en mémoire. Les lignes antérieures, remises et prix manuels ne sont pas réécrits.
- Styles différés dans sales-catalog.css, chargés avec ArcLoadStyle (le chargeur de styles existant), tokens Coco, cibles tactiles, champs nommés ; catalogue ES/FR/EN compilé. La charte du 23 octobre prévaut sur les anciens relevés visuels.
- Aucun nouveau moteur de stock, prix ou facturation. Pas de coût additionnel de service.

## Contrats

| API existante | Entrée | Sortie / limite | Accès |
| --- | --- | --- | --- |
| gama_sales_workspace : lookups | products + search | 30 produits actifs, références, taxes, unités, disponible global | Auth/MFA, sales_workspace_access |
| même API | products + ids | sélection rafraîchie, maximum 200 | même périmètre |
| gama_sales_workspace : prices | client/date, quantité de stock par produit | prix unitaire et règle via private.erp_price ; maximum 200 | mêmes contrôles |
| gama_quote_action : save | payload actuel de l'éditeur | devis, révision, dossier et historique | inchangé, serveur faisant autorité |

Quantité vendue × facteur = quantité stock (3 décimales). Prix conditionnement = prix unitaire serveur × facteur. Aucun coût d'achat supplémentaire exposé. Stock lu = disponibilité indicative, jamais une réservation ni une date promise. La capacité de sélection est bornée par le contrat de prix (200 lignes).

## États et garanties

Fermé → lecture → prêt/sélection → revalidation → ajout local → fermé. Erreur : sélection conservée, aucun ajout partiel. Recherche temporisée, réponses obsolètes rejetées, prix absent jamais remplacé par zéro. La sélection survit aux recherches.

À l'ajout : relire tous les produits actifs et les unités ; refuser un facteur modifié ; résoudre de nouveau les prix ; vérifier formulaire, session, client et date avant le callback unique. Les articles déjà dans le devis sont exclus. Retour/Échap ou changement de route/session abandonne le catalogue ; renouveler le jeton seul ne le ferme pas.

Les flux de confirmation, révision client, crédit, réservations, livraison, facture et paiement restent inchangés. Vendeur/admin éditent selon leurs droits actuels ; magasinier/client ne gagnent aucun accès. Les API contrôlent les droits réels.

Pas de mutation métier en production pendant cette livraison. Rechercher/sélectionner ne crée pas d'historique fictif. La sauvegarde humaine conserve l'historique existant. Toute exécution ultérieure par IA doit utiliser la passerelle/provenance Agent Coco définie dans AGENTS.md.

## Livraison

Sources via branche isolée. L'environnement local est devenu indisponible avant écriture ; les builds et tests exécutables sont donc effectués par les workflows CI habituels. Les sorties racine ne sont pas éditées à la main. Le workflow construit les sources, vérifie la reproductibilité puis publie dist.

Tests F01/F02 navigateur, régressions F03/F04 SQL isolées et PostgreSQL 17 concurrent en CI. Fusion après contrôles verts. Vérifier workflow de publication puis coco-build.json et actif catalogue réellement servi.

Retour arrière : revert de la PR et publication habituelle, sans opération SQL ni reprise de données. Les devis sauvegardés restent compatibles avec l'ancienne interface.
