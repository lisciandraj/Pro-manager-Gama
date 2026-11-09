# Ventes et comptabilité — extensions Community

La référence fonctionnelle est Odoo **19.0**, à partir de sa documentation
publique. Le code de Coco est original. La [matrice fonctionnelle](../../replica/community-2026-11-08/features.csv)
distingue les fonctions de ce lot, l’existant et le portail client retiré par
décision produit. Elle reste distincte de la matrice historique Enterprise des
rapports comptables avancés.

## Parcours commerciaux

- **Remise globale** : montant fixe ou pourcentage, réparti sur les bases fiscales
  et transmis aux factures partielles au centime. Les remises sont des lignes
  d’ajustement identifiées ; elles ne créent pas de faux produits en stock.
- **Livraison facturée** : tarif fixe ou règle utilisant poids, volume et distance,
  avec seuil de gratuité. La ligne de service suit le devis, la commande et la
  facture. Les coûts internes TMS restent des coûts.
- **Refacturation** : sélection d’une dépense réellement approuvée et comptabilisée,
  au coût hors taxes ou à un prix de vente. Le lien source interdit de facturer
  deux fois la même dépense et ne déclenche aucun remboursement supplémentaire.
- **Suggestions** : associations de produits optionnels ou alternatives supérieures,
  présentées à l’ajout du produit principal ; le commercial choisit explicitement
  de les retenir.
- **Promotions et fidélité** : programmes, codes, conditions, points et récompenses.
  Les points sont acquis sur les factures comptabilisées et corrigés par les
  avoirs ; les codes et usages sont contrôlés à nouveau à la confirmation.
- **Cartes cadeaux et portefeuilles** : financement par un encaissement client
  existant, suivi de la dette correspondante, puis consommation sur le véritable
  solde de facture. Aucun crédit de portefeuille n’est déclaré comme argent reçu.
- **PDF enrichis** : couvertures, fins de document, brochures de produits, annexes
  et champs de formulaire explicitement associés aux données commerciales.
  Les documents choisis sont figés à la finalisation du devis.

Voir les contrats [ajustements et refacturation](sales-commercial.md),
[fidélité et soldes](sales-rewards.md) et [exports PDF](../development/pdf-exports.md).

## Facturation et moteur fiscal

Les factures clients peuvent être créées directement en comptabilité, sans
commande fictive. Un brouillon ne crée ni écriture, ni créance, ni document SRI.
Les avoirs peuvent aussi être émis après paiement ; le remboursement réutilise le registre canonique, avec une limite partagée entre argent et restitution au portefeuille d’origine. La validation fige les lignes, les taxes, le tiers et les comptes ; les paiements,
rapprochements et avoirs consomment cette même facture.

Le moteur fiscal calcule les taxes en pourcentage ou fixes, les prix taxes
incluses, l’ordre des composantes, les taxes affectant la base suivante et les
arrondis par ligne ou globaux. Les positions fiscales substituent les taxes et
les comptes. Les montants proviennent des composantes calculées, sans taux
effectif inventé pour représenter des règles complexes.

Une facture déjà émise conserve ses comptes et taxes. Pour une nouvelle facture
issue d’une commande, un changement des règles fiscales exige une nouvelle
prévisualisation et une confirmation explicite. Les états fiscaux et le service
SRI gardent leurs propres contrôles de correspondance et de validité.

Les comptes de ventes et achats suivent l’ordre **produit → catégorie → société**,
indépendamment pour chaque côté. Les comptes clients/fournisseurs suivent le
paramétrage du tiers. Modifier ces préférences affecte les nouveaux documents,
jamais les écritures ni contre-passations déjà figées.

L’escompte définit un pourcentage, un délai, un compte et un traitement fiscal.
Le règlement distingue le montant effectivement reçu/payé de l’ajustement
commercial et fiscal ; les taxes sont ajustées à partir des instantanés d’origine.

## Signature et règlement à distance

Le lien commercial est une capacité limitée à un document précis, avec code
aléatoire, expiration et révocation. Le code brut n’est pas conservé en base.
Le destinataire consulte le PDF complet, annexes comprises ; le téléchargement
vérifie son empreinte SHA-256 avant d’autoriser la signature.

La signature commerciale peut être saisie, dessinée ou importée en PNG. Le nom,
la date serveur, la méthode et l’empreinte du PDF sont conservés. La confirmation
utilise le parcours de commande existant et les permissions courantes de
l’émetteur du lien. Si un contrôle commercial échoue, la preuve de signature
reste enregistrée et la commande attend la vérification de l’équipe commerciale.
Cette fonction ne réactive aucun compte ou portail client historique.

Les accès publics sont refusés dans une base non affectée ou de développement.
La prévisualisation en développement nécessite un administrateur actif vérifié
par le serveur. Une interface qui se déclare « production » ne peut modifier
cette règle.

Les instructions de virement ne valent pas preuve d’encaissement. Les paiements
prestataires doivent être confirmés côté serveur, avec contrôle du montant, de
la devise, du document et de l’unicité de l’événement. Les secrets marchands
restent dans la configuration sécurisée des fonctions serveur. Le compte
marchand, les clés et les URL de rappel doivent être configurés avant activation.

## Livraison et vérification

Les nouvelles tables sont privées ou protégées par RLS, avec contrôles de rôle,
MFA et périmètre. Les actions métier sont historisées ; une action Agent Coco
conserve sa provenance. Les tests reconstruisent des bases locales jetables et
utilisent les véritables fonctions SQL. Les tests navigateur couvrent français,
espagnol et anglais, sur petits et grands écrans.

Les migrations de ce lot sont des changements de schéma locaux au dépôt.
L’implémentation sur une branche ciblant `development` ne déploie pas les
migrations, n’active pas de prestataire et ne promeut pas la production.
Voir la [politique des environnements](../development/environments.md).

Les [rapports de chiffre d’affaires](accounting-revenue.md) suivent les produits comptabilisés et leurs contre-passations, avec dimensions clients/produits figées et reports à leurs dates. Le [contrat des encaissements à distance](checkout-payments.md) décrit l’activation, les réservations et la revue des événements de remboursement ou de litige.
