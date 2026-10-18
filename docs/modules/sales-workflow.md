# Ventes : dossier commercial, logistique et comptabilité

État du 15 octobre 2026. La carte **Ventes** propose cinq onglets visibles : **Devis**, **Commandes**, **À facturer**, **Analyse**, **Configuration** (administrateur). Les demandes clients restent un sous-onglet des devis ; **À traiter**, **Factures et encaissements**, **Tarifs** et **Matrice commerciale** ouvrent les modules existants. Les anciennes adresses et permissions restent compatibles. Les onglets passent sur plusieurs lignes sur téléphone ; les tableaux conservent leurs contours et leurs libellés en mode cartes.

Depuis le 18 octobre 2026, les demandes du site et du portail deviennent automatiquement des devis en brouillon, sans envoi, commande ni réservation. Les demandes originales restent liées ; les clients inconnus sont à compléter dans le brouillon. Voir [le parcours du site](../public-website.md#conversion-immédiate-en-brouillon).

## Observations vérifiées avant intervention

Le dépôt `lisciandraj/Pro-manager-Gama`, le site GitHub Pages et le projet Supabase `mknsaibrewksgomuslev` ont été identifiés. Le frontend est composé de modules JavaScript, d'un noyau Vite et d'un manifeste de compilation ; les sources sont dans `src/`. Le backend utilise les façades publiques invoker et les implémentations privées contrôlées.

Déjà opérationnels : tarifs négociés et paliers communs au portail, conditionnements, instantané d'acceptation, approbations commerciales, réservations à la confirmation, factures partielles/groupées dans `external_invoices`, préparation automatique vers TMS, preuves de livraison, retours, encaissements et rapprochements, suivi de processus. Ces chemins ont été réutilisés.

Partiels : le devis et sa commande avaient des identifiants distincts sans dossier commun ; la facturation était uniquement sur livré ; les états financiers ne distinguaient pas toujours écriture comptable et solde. Manquaient les sections/options, les acomptes et l'acceptation explicite depuis le portail. Le crédit d'une facture groupée risquait de diminuer plusieurs fois l'engagement restant. Une exception de crédit avant création de la commande issue du devis nécessitait un chemin explicite.

Les intégrations de signature électronique, paiement en ligne, programmes de fidélité et conversion monétaire n'ont pas été considérées opérationnelles sans preuve. Aucune valeur réglementaire n'a été inventée.

## Identité et états

`private.sales_dossiers` constitue la couche commune compatible avec `invoices` (devis) et `sales_orders`. Son UUID reste celui du devis lorsqu'il existe, sinon celui de la commande directe. `sales_dossier_lines` conserve les correspondances de lignes. Aucun ancien document ni préfixe n'est renuméroté. L'acceptation existante reste transactionnelle ; les préparations, livraisons, factures et paiements ne sont pas recopiés dans un nouveau registre concurrent.

Les états commercial, logistique, facturation et paiement sont calculés séparément. La préparation et l'expédition ne prouvent pas la réception client. La livraison facturable est celle de `private.gama_line_performed`, issue des lignes TMS avec preuve valide ou d'une prestation réalisée. Une facture active, y compris brouillon, réserve ses quantités ; son paiement ne peut rendre la commande payée qu'avec une écriture de facture comptabilisée. Le retard utilise les échéances existantes. L'expiration du devis reste un indicateur indépendant de la commande confirmée.

Le dossier conserve ses onglets opérationnels et son lien **Suivi de processus**. Les compteurs ouvrent les préparations, colis, livraisons, factures, encaissements et retours réellement liés. La planification des tournées reste dans TMS. Les activités datées (appel, relance, tâche, rendez-vous, note) ont un responsable et une clôture ; elles n'envoient aucun email automatiquement.

## Saisie et conditions

Le devis récupère le client et ses adresses existantes ; une destination ponctuelle ne modifie pas Contacts. La sélection produit recherche nom/référence/code-barres et permet **Ajouter et continuer**. Les quantités sont converties vers l'unité de stock selon les facteurs historiques validés par le serveur.

Sections et notes sont non facturables. Une option est exclue du total et devient une ligne normale après une action d'acceptation, avec le tarif courant et les taxes du produit. Les modèles conservent leurs sections/options et conditions dans une copie indépendante ; les documents émis ne suivent pas les modifications du modèle. Copier une vente crée un nouveau brouillon sans documents aval.

Un prix manuel conserve son motif et résiste au rafraîchissement du tarif, aux changements de date, quantité ou client. **Tarif automatique** réactive explicitement le moteur commun. Priorité : prix négocié client/produit, puis livres de prix applicables ordonnés par priorité, affectation client, spécificité produit avant catégorie, palier décroissant et identifiants stables ; sinon prix de catégorie client/catalogue. Une seule règle s'applique. Les paliers existants acceptent prix fixe, pourcentage ou formule (facteur, supplément, arrondi) sans créer un autre moteur. Les seuils d'approbation existants restent configurables et désactivés lorsqu'ils sont vides.

Devise et délai de paiement sont figés à l'émission/confirmation. Pour les documents historiques dont la preuve initiale manque, la provenance est explicitement `configuration_observed_at_migration` ; ce n'est pas une reconstitution certaine des conditions d'origine. La facturation dans une devise différente de celle de l'entreprise est bloquée tant que son traitement comptable n'est pas configuré.

## Facturation et crédit

**Configuration → Politiques de facturation** définit un défaut et des exceptions produit, copiés sur les nouvelles lignes. **Sur commandé** devient facturable à confirmation ; **sur livré** attend la preuve opérationnelle. Chaque ligne montre commandé, livré, retourné, facturé et restant facturable. Le cas de 20 toners à 50 USD HT donne 600 USD HT pour 12 livrés puis 400 USD HT pour 8 livrés.

**À facturer** offre recherche référence/client/produit, période, responsable, livraison partielle, facture partielle et blocages, avec pagination serveur de 30 dossiers. Les états de liste excluent les lignes détaillées et instantanés de factures. Le regroupement vérifie client, devise et conditions comptables ; le système conserve son modèle d'une seule société.

Un acompte fixe ou proportionnel utilise une facture interne du registre existant, sans ligne de marchandise ni livraison. Il requiert une **compte de passif pour acomptes** explicitement choisi en Configuration. Les factures de marchandises déduisent les acomptes disponibles par taux fiscal, une fois ; l'écriture finale reconnaît le revenu brut et solde le passif. Un acompte déjà déduit ne peut être annulé isolément. L'émission SRI d'acomptes ou de factures qui les déduisent est bloquée par `SRI_DEPOSIT_MAPPING_REQUIRED` tant que le mapping fournisseur n'est pas validé. Les autres factures conservent le connecteur SRI existant.

Le crédit utilise les créances actives et engagements non encore facturés, sans déduire deux fois une facture groupée. Les confirmations verrouillent le client et la transaction commerciale. Une dérogation administrateur exige un motif et une empreinte liée au devis et à son exposition ; une modification l'invalide. Une répétition de confirmation ne crée pas une autre commande ou préparation. Les créations utilisent une clé liée à l'acteur et au contenu ; réutiliser la clé avec un contenu différent est refusé.

## Portail et envoi

Le portail autonome conserve son identité client, sans profil ERP actif. Il peut consulter et accepter son devis valide avec date, auteur, révision et instantané. L'accord est présenté comme **en attente de confirmation par l'équipe** : le personnel confirme ensuite avec les contrôles de crédit habituels. Les identités de deux clients restent cloisonnées ; coûts, marges et notes internes ne sont pas ajoutés aux réponses portail.

Un document généré, un email préparé dans Gmail/Outlook et un envoi techniquement confirmé sont distincts. L'ouverture d'un brouillon ne constitue pas un envoi. Aucun nouveau fournisseur d'envoi, signature ou paiement n'est imposé.

## Analyse, sécurité et validation

Les montants commandés et facturés restent distincts. Les factures brouillon sont exclues du facturé comptabilisé ; les avoirs sont affichés séparément. Les définitions de période/population/taxes sont retournées par le serveur et affichées avec les indicateurs. La marge estimée utilise `private.order_cost_snapshots`, hors coût de livraison ; elle reste indisponible si un coût manque. Regroupements client/produit/catégorie/responsable et export Excel utilisent les composants existants.

`public.gama_sales_dossier` est invoker. Les fonctions privées vérifient session, MFA, profil, modules et actions ; les tables privées ont RLS et aucun accès direct. Le magasinier reçoit les quantités logistiques, sans coûts ni état financier. Aucune clé privilégiée n'est ajoutée au frontend.

Les migrations additives du 15 octobre s'appliquent dans l'ordre du dépôt après celles du 13 octobre. Les tests serveur `sales-dossier-db`, `sales-workspace-db`, crédit, stock/TMS, comptabilité et portail tournent sur des bases isolées ; `sales-concurrency.test.cjs` utilise deux connexions PostgreSQL 17 dans GitHub Actions. Les tests navigateur couvrent les cinq onglets, les prix manuels, les options, l'ajout multiple, la navigation et les formats FR/ES/EN sur téléphone. Voir [déploiement et retour arrière](../development/sales-dossier-rollout.md) pour les preuves de livraison et les limites.

## Discussion et analyse des mails

Les devis et commandes clients utilisent le [volet de discussion partagé à droite](order-followup.md) : étapes, statut, auteur/date, photo associée et notes. ChatGPT propose les actions issues des nouveaux mails dans cette discussion. La validation d’une demande de devis crée un seul brouillon avec les prix ERP, sans l’envoyer ou l’accepter. La connexion mail dans Supabase est retirée ; chaque boîte est connectée dans ChatGPT.
