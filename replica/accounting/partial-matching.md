# Méthodes nommées et rapprochements partiels

Référence fonctionnelle inchangée : **Odoo 19.0 Enterprise**, documentation officielle des [paiements](https://www.odoo.com/documentation/19.0/applications/finance/accounting/payments/online.html) et du [rapprochement bancaire](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/reconciliation.html), consultée le 26 octobre 2026. Implémentation originale, avec les données, droits, composants et traductions de Coco.

## Emplacements

Comptabilité → Configuration → Moyens de paiement : noms libres, plusieurs méthodes de même famille par compte/sens, traitement banque/attente/sans écriture, activation et défaut par famille. La préférence d'un client ou fournisseur se configure dans le même panneau. Le formulaire de règlement client ou fournisseur propose la méthode du contact ; une sélection explicite la remplace. Encaissements et acomptes propose également les méthodes nommées.

Comptabilité → Banque et caisse → Rapprochement groupé : montants sélectionnables, aperçu daté, portions encore disponibles et annulation motivée d'un groupe. L'aperçu distingue les écritures selon chaque date bancaire ; le détail d'un groupe donne accès aux écritures par date.

## Règles et intégration

Les tables canoniques des paiements, acomptes, factures et groupes de rapprochement sont conservées. Le paramètre facultatif `payment_method_id` sélectionne une méthode nommée ; `method` conserve les familles historiques. Les appels sans nouvelle sélection gardent leurs anciens contrats. Le traitement, les comptes et le nom de méthode sont figés sur le paiement. Renommer, désactiver ou changer le traitement futur d'une méthode ne réécrit aucune pièce passée. Un rejeu de la requête initiale retrouve sa réponse, même après désactivation de la méthode.

Un groupe peut consommer une partie d'une ligne bancaire et d'un paiement. Le solde restant est le montant initial moins les portions des groupes actifs. Le verrou du compte financier et les verrous des sources sérialisent les utilisateurs. Les doublons de sélection, dépassements, signes incorrects et distributions incohérentes annulent entièrement l'opération.

La table privée d'affectations lie chaque portion à son mouvement bancaire. L'allocation automatique suit les dates bancaires et l'ordre présenté par l'aperçu. Pour plusieurs mouvements et des sources de signes différents, l'utilisateur saisit la répartition par mouvement ; chaque somme bancaire et chaque somme source doit correspondre au montant sélectionné. Les frais restent des dépenses réelles, sans écriture d'équilibrage inventée.

Une méthode en attente solde le tiers à l'enregistrement et transfère seulement le montant rapproché vers la banque. Sans écriture, seul le montant effectivement rapproché réduit le reste dû. Les transferts ont chacun la date bancaire réelle. Chaque mouvement bancaire conserve sa ligne au grand livre : une entrée de 100 et une sortie de 100 le même jour donnent un débit bancaire de 100 et un crédit bancaire de 100, même si leur solde net est nul. Une date fermée ou décalée par un verrouillage bloque le lot ; elle n'est jamais remplacée silencieusement par la date du dernier mouvement. Les sources déjà comptabilisées en banque ne produisent pas de deuxième encaissement.

Un acompte sans écriture peut être affecté à hauteur du crédit réellement rapproché. Son montant non rapproché reste indisponible. Défaire un rapprochement utilisé par une affectation exige d'abord de libérer cette affectation. La dette et le paiement bancaire restent distincts.

Annuler un groupe remet uniquement ses portions à disposition et contre-passe ses propres écritures ; les autres groupes et leurs écritures restent effectifs. Les anciennes correspondances entières sont conservées et restent annulables. Un bouton historique sur une ligne comportant plusieurs groupes exige de choisir le groupe dans la vue groupée.

Les nouvelles tables privées ont RLS et aucun accès direct pour les rôles clients. Les façades publiques restent invocatrices ; les traitements internes contrôlent Auth, MFA, rôle, périmètre et droits. La configuration proposée par Agent Coco reste soumise à une approbation humaine ; cette extension ne raccorde pas encore ces paramètres à la file de propositions (N02 reste partiel).

## Preuves et limites

- Scénarios chiffrés indépendants : 100 = 40 + 60 ; mouvement bancaire 150 = 100 + 50 ; deux dates ; fournisseur ; acompte ; frais 3 pour encaissement net 97 ; annulation d'une portion ; droits, requêtes rejouées et verrouillages.
- Base de reprise peuplée avant migration : empreintes identiques des écritures, lignes, paiements, banques, groupes et paramètres historiques ; ancien rapprochement annulé ensuite avec une seule contrepassation.
- PostgreSQL 17 à deux connexions : deux paiements de 100 ne consomment pas simultanément une ligne de 150 ; la seconde utilisation est limitée aux 50 restants.
- Neuf parcours d'interface ES/FR/EN × 390/768/1440, avec les RPC réelles en base isolée, contrôle axe et captures. Le panneau d'historique commun et la charte Coco restent réutilisés.

Les fichiers de lots, la synchronisation bancaire, les prestataires de paiement, le moteur complet de rapprochement automatique et la conversion multi-sociétés ne sont pas livrés par ce lot. Ils restent inscrits dans la matrice. Aucun taux fiscal, RUC ou comportement SRI n'est ajouté.
