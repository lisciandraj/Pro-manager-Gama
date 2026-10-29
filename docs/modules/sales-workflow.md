# Ventes : dossier commercial, logistique et comptabilité

État du 15 octobre 2026. La carte **Ventes** propose cinq onglets visibles : **Devis**, **Commandes**, **À facturer**, **Analyse**, **Configuration** (administrateur). Demandes clients et devis partagent un seul tableau dans **Devis** ; **À traiter**, **Factures et encaissements**, **Tarifs** et **Matrice commerciale** ouvrent les modules existants. Les anciennes adresses et permissions restent compatibles. Les onglets passent sur plusieurs lignes sur téléphone ; les tableaux conservent leurs contours et leurs libellés en mode cartes.

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

## Tableau unique des demandes et devis

Depuis le 18 octobre 2026, les anciens sous-onglets Demandes clients et Devis sont fusionnés. Une demande sans devis et un devis en brouillon apparaissent sous leur référence **SOL**, avec l’état **Demande client**. Dès que l’équipe finalise le brouillon, la même ligne affiche sa référence **COT**. Enregistrer le brouillon ne le finalise pas. Une réouverture reprend la même référence SOL. La validation commerciale des conditions reste distincte de la finalisation.

Les demandes déjà liées à un devis ne créent jamais une seconde ligne. Le total, les filtres, la recherche et la pagination portent sur cette liste commune. Les références SOL et COT restent recherchables après validation ; les numéros historiques COT, les demandes originales, les dossiers et leurs liens sont conservés. Un brouillon saisi directement reçoit sa propre référence SOL via le générateur existant, sans créer une demande technique supplémentaire. Les anciennes adresses ouvrent le même tableau, et les liens précis vers une demande ouvrent son détail avec retour au tableau.

Les anciens brouillons sans état de devis moderne suivent la même règle SOL. Les archives déjà émises conservent COT et l’état Document antérieur ; leurs montants et états enregistrés ne sont pas réécrits.

## Catalogue de devis

Depuis l'éditeur d'un brouillon, **Catalogue du devis** permet de sélectionner plusieurs produits, puis de les ajouter en une fois. Choisir d'abord le client. La recherche serveur affiche jusqu'à 30 résultats par recherche ; la sélection est conservée entre recherches et peut être revue avec **Voir la sélection**. Jusqu'à 200 produits au total dans ce parcours.

Pour chaque article sélectionné, le conditionnement et la quantité déterminent la quantité de stock envoyée au moteur tarifaire commun. Le prix affiché est celui du conditionnement, hors TVA. La disponibilité est une photographie non réservée ; un manque est signalé et les services sont distingués. Aucune date de livraison n'est promise. Produits/unités/prix sont relus avant ajout ; une erreur ne crée aucune ligne partielle.

Les produits déjà présents restent dans leurs lignes, avec leurs prix manuels et motifs. Le catalogue ne les fusionne pas. **Retour** abandonne la sélection ; **Ajouter la sélection** modifie seulement le brouillon à l'écran. La sauvegarde et l'historique utilisent le parcours existant. Le site public, la confirmation et les règles de crédit/stock/facturation ne changent pas.

Étude, limites et validation : [comparaison distribution](../../replica/distribution-2026-10-23/recon.md).

## Suivi, marges et engagements de distribution

La liste des devis affiche la prochaine activité ouverte du dossier : titre,
responsable, échéance et retard. Les activités datées précèdent celles sans date.
La clôture est idempotente et rejoint l'historique du dossier.

L'éditeur affiche une marge estimée par ligne pour les profils autorisés aux
finances, issue du même service que la marge totale. Un coût inconnu reste
inconnu. Les prix manuels, motifs, conditionnements et versions ne changent pas.

**Disponibilité prévue** dans le devis et **Disponibilité et accords** dans la
commande ouvrent une projection en lecture seule. Elle utilise les quantités
physiques libres, les réservations propres à la commande, les engagements
confirmés antérieurs et les achats envoyés/partiels encore à recevoir. L'ordre
FIFO est celui du moteur d'allocation existant. Les arrivages en retard ou sans
date sont signalés et ne fondent pas une promesse. Les services ne reçoivent pas
une date de stock. Les cartes mobiles montrent les mêmes données que le tableau.

La préparation et le transport sont saisis en **jours calendaires** ; aucune
heure de tournée, durée interurbaine ou règle de jours fériés n'est présumée.
Une proposition de livraison partielle utilise la quantité concernée. Le serveur
recalcule la date à la proposition et à l'accord, sans réserver un arrivage futur.

Les substitutions utilisent `sales_fulfillment_options` et le moteur de reliquats
existant. Le tarif client est proposé automatiquement ; un prix manuel nécessite
un motif. Le devis accepté reste inchangé. Un administrateur peut approuver les
conditions commerciales exactes ; l'accord du client doit encore être référencé
par le vendeur et le crédit est recontrôlé si l'exposition augmente. Une quantité
réservée, préparée ou facturée reste protégée par les règles existantes. Une
modification du dossier ou des coûts après approbation empêche l'application
silencieuse de l'ancienne proposition. La réponse répétée est idempotente.

Le portail B2B conserve ses droits et ses parcours actuels : cette livraison
n'ajoute aucun bouton d'acceptation de substitution au portail et ne réactive pas
les anciens comptes client ERP. Aucun message client n'est envoyé par ces actions.

Les notifications et priorités existantes ajoutent les activités commerciales
en retard, accords en attente et engagements de livraison dépassés. Le magasinier
voit les engagements logistiques ; les éléments commerciaux restent filtrés.
Les options et leurs conditions utilisent l'index d'historique expurgé existant,
avec la provenance Agent Coco lorsque le contexte d'exécution la fournit.

Contrats et limites : [architecture du lot distribution](../../replica/distribution-2026-10-23/remaining-architecture.md).
