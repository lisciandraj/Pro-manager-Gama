# Relevés OFX, QIF, CAMT.053, CODA et Excel

Référence : Odoo 19.0 Enterprise, [transactions bancaires](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/transactions.html), consultées le 27 octobre 2026. Les six formats CSV, XLSX, OFX, QIF, CAMT.053 et CODA appartiennent au périmètre. La synchronisation bancaire reste distincte.

Sources publiques : [OFX Banking 2.3](https://financialdataexchange.org/common/Uploaded%20files/OFX%20files/OFX%20Banking%20Specification%20v2.3.pdf), [Quicken QIF](https://info.quicken.com/win/why-can-t-i-import-data-from-a-qif-file-into-a-ban), [documentation historique QIF](https://www.w3.org/2000/10/swap/pim/qif-doc/QIF-doc.htm), [catalogue ISO 20022](https://www.iso20022.org/iso-20022-message-definitions?search=camt.053), [standards Febelfin](https://febelfin.be/en/publications/2023/febelfin-banking-standards-for-online-banking). CODA 2.8 conserve le code de version 2. Aucun code ni contenu propriétaire Odoo n'est intégré.

## Parcours Coco

Dans Comptabilité → Banque et caisse → Importer un relevé, choisir le compte Coco, le fichier et, si nécessaire, le compte présent dans le fichier ou la feuille Excel. QIF exige un ordre de dates explicite. L'aperçu expose les lignes, la devise et les soldes disponibles. CSV et XLSX conservent l'affectation manuelle des colonnes. La confirmation seule transmet les lignes à la base.

Les comptes bancaires et la devise viennent des paramètres réels. Aucun taux de change ni compte comptable n'est inventé. Les fichiers limités à 2 Mo et 1 000 mouvements sont analysés localement ; XLSX utilise le lecteur SheetJS déjà fourni et un worker limité dans le temps. Les formules ne sont pas importées comme valeurs vérifiées.

Les identifiants fournis par les banques sont isolés par compte Coco, compte source et format. Sans identifiant, une empreinte du mouvement et son numéro d'occurrence préservent deux paiements identiques. Réimporter un même fichier ne duplique pas les écritures. Réutiliser un identifiant avec un autre montant ou une autre date bloque le lot. Une ligne ancienne reconnue reçoit sa provenance sans recréation.

CAMT et CODA retiennent une seule transaction par mouvement comptable, sans compter deux fois les détails d'un lot. Les soldes disponibles sont rapprochés de la somme en centimes entiers. Les dates civiles du fichier sont conservées. XML refuse les déclarations DTD et les entités externes. Les erreurs sont disponibles en français, espagnol et anglais.

## Architecture et migration

`private.accounting_statement_sources` conserve la provenance, avec RLS et sans accès direct des rôles applicatifs. `gama_bank_statement_import` est une enveloppe invoker ; la mutation privée vérifie les droits Coco, MFA, portée, compte, devise, lignes et clé de requête. Elle verrouille le compte bancaire, puis réutilise le moteur existant d'import et, lorsqu'il est configuré, de banque/attente. Un échec annule l'ensemble.

L'historique de la provenance est capturé et renvoie vers le mouvement bancaire. La liste des comptes expose désormais leur devise réelle. Aucun fournisseur, abonnement ou accès réseau supplémentaire n'est nécessaire pour ces lecteurs.

Migration additive : aucune modification de facture, de paiement, de rapprochement ou de solde existant. Avant application, conserver les fonctions remplacées et les empreintes des 30 tables comptables suivies ; comparer après. Archiver exactement la version et le SHA256 affectés par Supabase. Aucun import de test en production.

Retour arrière : republier le dernier artefact web validé pour désactiver le formulaire étendu. Conserver les provenances et les écritures déjà importées ; ne pas supprimer la table ni retirer ses contrôles. Toute correction de mouvement utilise les mécanismes métier de rapprochement/contrepassation existants.

## Vérification et limites

Les tests emploient uniquement des fichiers synthétiques et des bases isolées. Les résultats, le commit et la migration effectivement publiés seront conservés dans `results-bank-formats.md` après les contrôles CI.

F04 reste **partiel**, sans changement discret du périmètre : les corrections OFX exigent une revue, les fichiers CODA d'applications séparées et certaines variantes multi-extraits ne sont pas encore pris en charge ; les variantes propres à chaque banque restent à comparer. Les opérations sur compte bancaire en devise étrangère relèvent de J03. Une variante refusée affiche une erreur et ne produit aucune écriture.
