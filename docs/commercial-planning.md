# Rentabilité, récurrence, trésorerie, relances et OCR

Ces extensions complètent les parcours commerciaux et comptables existants. Les écrans ERP suivent la langue FR/ES/EN ; le portail client conserve sa langue espagnole.

## Rentabilité et devis

**Comptabilité → Rapports → Rentabilité par commande et client** sélectionne les commandes créées sur la période (366 jours maximum). Les remises sont déjà incluses dans les prix nets des lignes. La marge prévue utilise le coût d’achat mémorisé à la création de la ligne ; pour les anciennes lignes sans instantané, le coût courant reste une estimation. Un changement de produit capture son nouveau coût.

La vue facturée déduit les avoirs et utilise les coûts historiques des sorties de stock. Les retours remis en stock et crédités réintègrent le coût correspondant. Un coût historique absent rend la marge indisponible. Les coûts de préparation, livraison, retours et autres frais se saisissent avec nature estimée/constatée et justificatif. Une livraison saisie remplace l’estimation de tournée ; celle-ci est répartie en centimes entre les arrêts. « Marge sur coûts connus » ne constitue pas un bénéfice net : les coûts manquants sont signalés, et préparation/livraison doivent être constatées pour afficher des coûts complets.

Le formulaire de devis affiche la marge estimée sur les produits, avant préparation et livraison, et signale un résultat sous le seuil paramétré. Il ne bloque pas l’enregistrement. Les commerciaux autorisés aux devis peuvent voir cette estimation ; les résultats détaillés exigent le périmètre comptable complet.

## Commandes récurrentes

**Ventes → Commandes → Commandes récurrentes** consulte et suspend les programmes. Dans une commande, **Programmer cette commande** reprend ses lignes. Dans le portail, **Ma sélection → Programar esta selección** crée un programme hebdomadaire ou mensuel, avec intervalle, date, adresse et quantités. **Pedidos recurrentes** permet de modifier le programme et de traiter ses propositions.

Le traitement horaire prépare une proposition par programme arrivé à échéance. Il ne commande rien. Le client doit ouvrir la proposition, vérifier les prix négociés actuels et confirmer. Une modification de quantité impose un nouveau calcul des prix. La confirmation crée une seule demande client par proposition, même après une réponse réseau perdue. Le parcours devis, acceptation, contrôle de crédit et commande reste celui du dossier commercial. Suspendre/modifier un programme annule ses anciennes propositions en attente. Sauter une date avance le programme. Les dates mensuelles conservent le jour d’ancrage, y compris après février. Le périmètre client est dérivé de l’association B2B authentifiée.

## Trésorerie sur 13 semaines

**Comptabilité → Rapports → Trésorerie · 13 semaines** projette le solde des comptes actifs, les échéances clients et fournisseurs restantes, les achats engagés non encore facturés et les paies validées non payées. Les achats déjà facturés sont soustraits des engagements pour éviter leur double comptage. Les dates manquantes et les retards sont présentés dès la première semaine.

Ajouter les futures paies, charges, loyers et autres engagements qui ne sont pas encore enregistrés. Un engagement mensuel peut avoir une date de fin et être désactivé. Éviter de recopier une charge déjà comprise dans une facture ou une paie validée. Les scénarios décalent encaissements/décaissements, appliquent un pourcentage de recouvrement et un solde minimal. Ils ne modifient ni échéances réelles, ni paiements, ni comptabilité. La projection utilise la devise de l’entreprise et ne convertit pas des devises étrangères.

## Relances programmées

**Comptabilité → Créances → Relances programmées** règle les étapes en jours autour de l’échéance (exemple −3, +7, +14, +30), la langue, le mode manuel/automatique et les litiges/promesses/suspensions. L’historique est partagé avec les mails préparés. La prochaine échéance impayée sert de référence ; chaque étape est unique par facture et échéance. Seule la dernière étape applicable est préparée lors d’un passage, sans rattrapage massif.

Les règles restent désactivées tant qu’un administrateur ne les active pas. Le mode automatique nécessite un fournisseur Resend activé, un domaine/expéditeur vérifié et une clé serveur conservée dans Vault. Les préférences de rappels de chaque client doivent également être actives. Aucune migration n’active un fournisseur, une règle ou une préférence et aucun ancien brouillon n’est mis en envoi. La délégation autorisée expire après 90 jours et doit être renouvelée. Le mode manuel conserve les liens Gmail/Outlook et la confirmation manuelle existante.

Avant chaque envoi, le serveur revérifie droits, délégation, solde, destinataire, préférence, litige et promesse. Une modification invalide le message non envoyé. Un paiement total arrête les rappels. Les tentatives après interruption conservent la même clé d’idempotence ; après la fenêtre de reprise, l’état demande une vérification chez le fournisseur. « Accepté » et « distribué » restent deux états différents. Désactiver le fournisseur arrête son traitement planifié.

## Factures fournisseurs PDF/photo

**Comptabilité → Achats → Lecture de factures PDF / photo** accepte PDF, JPEG, PNG et WebP jusqu’à 5 Mo. L’Edge Function `coco-supplier-ocr` utilise la clé et le modèle IA déjà configurés pour l’assistant, avec autorisation comptable du demandeur. Le fichier est transmis à l’API d’extraction avec `store:false` et sans outil d’action. Cela n’est pas une vérification fiscale SRI.

L’original reste dans un stockage privé SQL accessible uniquement par le RPC contrôlé. L’empreinte du contenu évite les doublons et une réservation empêche les extractions concurrentes. Les tentatives sont limitées à 20 par utilisateur sur 24 heures, reprises incluses. L’extraction laisse les champs inconnus vides et conserve ses avertissements. La revue permet de corriger fournisseur, achat, numéro, dates, devise et montants, puis compare facture/achat/réception. Les lignes extraites servent à la vérification du document ; les correspondances comptables aux lignes d’achat se complètent ensuite dans le parcours existant.

La confirmation explicite de la revue crée un brouillon fournisseur unique, jamais une écriture ni un paiement. Le contrôle existant des réceptions/lignes et la validation comptable restent nécessaires. L’original demeure consultable depuis l’historique OCR, y compris après création du brouillon.

## Déploiement et vérification

Appliquer dans l’ordre les migrations `commercial_profitability_and_cash_scenarios`, `recurring_customer_orders`, `scheduled_collection_sequences` et `supplier_document_ocr_review`, puis `collection_sequence_stage_revalidation`, et déployer `coco-supplier-ocr` avec JWT activé. Publier les actifs ERP et le portail Cloudflare issus du build. Les tables d’extension se trouvent dans `private`, avec RLS et sans accès direct pour les utilisateurs. Les façades authentifiées contrôlent les droits et MFA à chaque appel. Les réglages de planification sont audités, les clés et fichiers bruts exclus du journal.

Validation : `tests/commercial-growth-db.test.cjs`, `tests/supplier-ocr-edge.test.mjs`, parcours complémentaires de `tests/accounting.spec.js` et `tests/b2b-portal.spec.js`, puis `npm run update`. Les fixtures d’envoi ne contactent aucun fournisseur ; les fixtures OCR ne facturent aucune extraction réelle. Aucun essai de ces suites ne crée de facture, commande ou message en production.
