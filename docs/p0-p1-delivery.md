# Architect ERP — livraison P0/P1

Périmètre demandé le 20 septembre 2026, base `d455cd0`. Les lignes ci-dessous
couvrent les critères P0/P1 recensés. Les fonctions P2 de l’assistant IA et de la
base de connaissances sont hors périmètre. Les fonctions déjà présentes ont été
conservées ; les contrôles et parcours manquants ont été ajoutés.

État : version validée ; base de production et fonction serveur déployées le 20 septembre 2026. Publication de l’interface en cours.
Autorisation explicite de publication directe en production reçue dans la conversation.

## Couverture fonctionnelle

| Module | Résultat et parcours disponible | Principales preuves |
|---|---|---|
| Accueil | Données chargées à l’ouverture du module, menu indépendant des KPI, SDK servi localement, diagnostic de durée sans données métier | `loading-performance.spec.js`, `loading-performance.test.cjs`, `src/app/performance.js` |
| Tableau de bord | Période commune, vues direction/commercial/logistique, horodatage, détail paginé des KPI principaux, acomptes sans double comptage | `dashboard-db.test.cjs`, `dashboard-analysis.spec.js`, `p1-finance-db.test.cjs` |
| Opérations | Impact/urgence, cause, responsable, prochaine action, échéance, escalade, historique de résolution/réouverture | `gama-operations.js`, migration `p1_alert_followup_and_operating_controls`, `operations.spec.js` |
| Notifications | Préférences par famille, informations/actions, regroupement et suivi partagé avec les opérations | `gama-operations.js`, `p1_transport_proofs_and_notification_preferences` |
| CRM | Fusion contrôlée avec aperçu, opportunités inactives, contexte client, distinction potentiel pondéré/gagné/facturé | `architect-partners.js`, `p1_commercial_controls_and_merge`, tests `crm-*` |
| Clients | Adresses/contacts, encours/plafond/blocage, dérogation approuvée, historique transversal, fusion auditée | `architect-partners.js`, `p1-controls-db.test.cjs`, `p1-new-workflows.spec.js` |
| Produits | Unité de base et conversions fixes, articles/prestations, historique des prix, lots optionnels avec péremption et mouvements tracés | `architect-products-controls.js`, `architect-service-products.js`, `architect-lots.js`, tests DB services/lots |
| Tarifs | Validité, quantité, catégories/clients, priorité explicite, explication du prix, approbation et versions immuables | `architect-pricing.js`, `p1-pricing-db.test.cjs` |
| Matrice | Scénarios centralisés, coût rendu, marge sur prix de vente, conservation des simulations et contrôle du prix avant application | `gama-proveedores-matriz.js`, `p0-integrity-db.test.cjs` |
| Devis | Copie figée à l’acceptation, remises/marges soumises à approbation, prix expliqués/recalculables, disponibilité et types de documents explicites | `gama-quotes.js`, `gama-quote-pdf.js`, `p1-controls-db.test.cjs`, `client-quotes.spec.js` |
| Commandes | Quantités réservées/expédiées/facturées par ligne, promesses, modifications contrôlées, allocation par ancienneté ; registre distinct des prestations | `sales-orders.spec.js`, `p1-service-products-db.test.cjs` |
| Dossier | Prochaine action/responsable/date, documents partiels, écarts entre étapes, clôture contrôlée et réouverture si les données changent | `architect-project-controls.js`, `p1_dossier_and_project_followthrough`, `dossier-flow.spec.js` |
| Paiements | Compte financier réel obligatoire, acomptes et affectations, rapprochements, promesses/litiges, référence externe sans seconde facture | `architect-finance-controls.js`, `p1-finance-db.test.cjs`, `payments.spec.js` |
| Catalogue client | Recommande, saisie par référence, minimum/multiple/date demandée, prix calculé au serveur, visibilité du stock réglable | `gama-client-catalog.js`, `p1-pricing-db.test.cjs`, `catalog-cart.spec.js` |
| Livraisons client | Détail/quantités/preuves, réclamation liée, fil public isolé du fil interne, suivi des prestations de son propre compte | `architect-service-workflows.js`, `architect-service-products.js`, tests services |
| Fournisseurs | Offres par article, comparaison et préparation d’achat, performance calculée sur réceptions observées | `architect-sourcing.js`, `p1-controls-db.test.cjs` |
| Achats | Enregistrement transactionnel, taxes au serveur, relance idempotente des réceptions, approbations, rapprochement commande/réception/facture | `gama-purchases-v14.js`, tests intégrité/contrôles/services |
| Entrepôts | Stock local et entrées destinées à l’entrepôt, projection datée, lectures paginées et agrégats serveur, réapprovisionnement | `gama-inventory-v2.js`, `p0-integrity-db.test.cjs`, tests inventaire |
| Mouvements | Commandes idempotentes, référence d’origine, motif et approbation des ajustements, traçabilité automatique des lots | `architect-stock-controls.js`, `p1-stock-db.test.cjs`, `p1-lots-db.test.cjs` |
| Inventaires | Comptages tournants/aveugles, vérification du stock observé, recomptage par une autre personne, validation des écarts | `p1-stock-db.test.cjs`, `inventory-count.spec.js` |
| Codes-barres | Article/conditionnement/colis, identification, contrôles GTIN, Code39 corrigé, PDF par lots sur deux formats | `architect-barcode-controls.js`, `p1-new-workflows.spec.js` |
| Préparation | Ordre des emplacements, attribution/concurrence, incidents/manquants, confirmation courte et vérification des lots prélevés | `gama-fulfillment.js`, `fulfillment.spec.js`, tests lots |
| Transport | Trajets routiers renseignés et sourcés, temps de service, incidents, preuves conservées localement avant synchronisation, historique | `architect-transport-controls.js`, `architect-offline-proofs.js`, `p1-controls-db.test.cjs`, `tms-module.spec.js` |
| Flotte | Disponibilité, documents, coûts liés à la comptabilité, consommation/coût kilométrique, prochaine maintenance datée/kilométrée | `gama-fleet.js`, `fleet.spec.js` |
| Retours | Remboursement sur compte réel, remplacement, quarantaine, historique des dispositions et lots | `gama-returns.js`, `p0-integrity-db.test.cjs`, `returns.spec.js` |
| SAV | Retour/remplacement/remboursement liés, SLA configurables, public/interne, causes, échéances conservées pour les dossiers existants | `p1-service-db.test.cjs`, `service-documents.spec.js` |
| Comptabilité | Rapprochements groupés/fractionnés avec frais documentés, contrôle achat/réception, valorisation historique, vérifications de clôture | `p1-finance-db.test.cjs`, `p1-controls-db.test.cjs`, `accounting.spec.js` |
| Projets | Main-d’œuvre/autres coûts, achats/frais/factures sans double comptage, recettes, versions de référence, vue simple par défaut | `architect-project-controls.js`, `p1-controls-db.test.cjs`, tests projets |
| RH | Effectif minimal, tâches d’entrée/sortie, compétences et expirations, transmission des responsabilités sans modifier l’auteur historique | `architect-people.js`, `p1-people-db.test.cjs`, `hr-p1.spec.js` |
| Documents | Recherche, approbation d’une version précise, propriétaire/prochaine action/expiration, droits du document source | `architect-service-workflows.js`, `p1-service-db.test.cjs`, `document-library-db.test.cjs` |
| Import | Simulation complète, erreurs par ligne, reprise des seules lignes en erreur, identité du lot, catégories client | `gama-excel-import-v1.js`, `p1-import-db.test.cjs` |
| Audit | Avant/après transversal, réglages sensibles, recherche, ouverture de la source quand elle existe, export | `architect-audit.js`, `audit-trail.spec.js` |
| Utilisateurs | Invitation manuelle via fonction serveur, comptes invités inactifs, récupération, désactivation/révocation, MFA, transfert des dossiers ouverts | `architect-identity.js`, `architect-people.js`, `identity-admin.test.mjs`, tests utilisateurs |
| Accès | Restrictions créer/modifier/supprimer/valider/exporter, périmètres métier existants, aperçu et revue datée/versionnée | `architect-access-controls.js`, `p1-controls-db.test.cjs`, tests profils/permissions |
| Configuration | Seuils métier, fuseau partagé, vérification de version avant enregistrement, historique des règles sensibles | `architect-controls.js`, tests contrôles/configuration |
| Sauvegarde | Export des tables métier et états privés, fichiers et sommes de contrôle, restauration isolée des liens/séquences | `architect-recovery.js`, `scripts/restore-application-export.cjs`, `p0-recovery-db.test.cjs` |

## Limites opérationnelles explicites

- Les temps routiers sont saisis après vérification d’un itinéraire ; aucun service
  cartographique payant ou calculateur routier externe n’est activé implicitement.
- La valorisation historique utilise le coût standard enregistré à partir de
  l’instantané initial. Elle ne reconstitue pas de coûts antérieurs ni un FIFO comptable.
- Le suivi des lots est optionnel, démarre à stock nul et nécessite l’identification
  des réceptions. Les prélèvements suivent la péremption puis l’ancienneté et demandent
  une confirmation des codes. Aucun lot historique n’est inventé.
- Les SLA sont exprimés en heures écoulées ; une modification s’applique aux nouveaux
  tickets et ne change pas leurs échéances historiques.
- La sauvegarde applicative exclut les secrets, identifiants d’authentification et la
  configuration d’infrastructure. Le test de restauration concerne une base isolée.
  Les sauvegardes physiques/PITR du fournisseur ne sont pas certifiées par ce test.
- L’invitation n’envoie un email que lors de l’action explicite de l’administrateur.
  Aucun email réel n’a été envoyé pour les essais.
- Les périmètres de lecture restent ceux des modules ; les restrictions d’action
  réduisent les droits existants sans accorder un nouveau périmètre de données.

## Validation

- 69 tests Node/PostgreSQL passent ; ils rejouent les migrations réelles dans PGlite.
- Le contrôle de schéma recense 162 tables publiques, toutes protégées par RLS.
- Tests additionnels du tableau de bord : total des détails identique au KPI,
  acomptes reconnus une seule fois dans les encaissements et comptes financiers.
- Vérifications de sources, TypeScript, historique des migrations et compilation.
- Campagne web : 576 cas, dont 539 réussis au premier passage, 36 corrigés et revalidés dans les reprises ciblées, et 1 ignoré. Les corrections concernent les fixtures des nouveaux RPC/parcours et deux accès directs affectés par le chargement différé (utilisateurs et édition produit).
- Reprises ciblées finales : 29, 19, 32, 53, 22 et 6 cas réussis selon le lot ; ces chiffres se recoupent et ne s’ajoutent pas aux 576 cas.

## Déploiement

- Projet Supabase : `mknsaibrewksgomuslev` ; 23 migrations P0/P1 appliquées, 179 migrations dans l’historique synchronisé.
- Fonction `architect-user-admin`, version 1, active, vérification JWT activée.
- Contrôle de production : 162 tables publiques, aucune sans RLS ; aucune fonction publique SECURITY DEFINER exécutable par `anon`.
- Le conseiller de sécurité ne signale plus d’erreur. Son avertissement préexistant sur la détection des mots de passe compromis reste un réglage Supabase Auth à activer : [documentation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Les tables privées sans politique restent volontairement interdites en accès direct.
- Interface : publication depuis `main` sur https://lisciandraj.github.io/Pro-manager-Gama/. Vérification du déploiement et des empreintes des fichiers après publication.
