# Comptabilité Coco : comparaison et mise à niveau Équateur

Date de vérification : 2 octobre 2026. Référence : Odoo **Community 19.0**, dépôt public `odoo/odoo`, localisation `l10n_ec`. La documentation commerciale Odoo décrit aussi des modules supplémentaires ; leur présence dans cette documentation ne prouve pas leur disponibilité dans Community.

## État réel avant modification

La base `mknsaibrewksgomuslev` contient 14 factures de vente, zéro écriture comptable, zéro facture fournisseur, zéro dépense, zéro paie et zéro valorisation FIFO/AVCO. Un mois est fermé. Le pays est EC et la monnaie USD. L’identifiant fiscal de l’entreprise ne comporte pas 13 chiffres.

Ces observations sont des comptages en lecture seule. Aucun mois existant n’est rouvert, aucun solde commercial n’est corrigé et aucune pièce fiscale n’est inventée par la migration. Les nouvelles écritures issues des actions métiers sont créées dans leur transaction ; la reprise d’anciens documents continue de respecter les périodes fermées.

Les contrepassations avaient **déjà été corrigées** dans les migrations P1 : les rapports comptent l’original et sa contre-écriture. Le plan équatorien de **501 comptes** était également présent dans `config/localizations/EC.json`. Son empreinte correspond au CSV officiel relu pendant cet audit. Ces éléments sont conservés.

## Comparaison fonctionnelle

| Fonction | Situation Coco avant | Résultat de cette modification |
|---|---|---|
| Comptabilité en partie double, journaux et comptes | Présente | Conservée ; blocage du changement de type d’un compte déjà utilisé et des comptes inactifs |
| Plan de comptes équatorien | Modèle 501 comptes déjà présent, installation avant première écriture | Import complémentaire volontaire, sans remplacement des comptes occupés ni changement des correspondances automatiques |
| Factures, paiements, fournisseurs, dépenses et retours | Liens présents ; ventes et certains retours repris à l’ouverture du module | Déclencheurs transactionnels lors des enregistrements ; annulation de l’écriture avec le document d’origine |
| Grand livre | Liste d’écritures et détail | Livre paginé avec solde d’ouverture et solde progressif ; export de toutes les pages |
| Balance | Bilan de gestion simplifié | Balance par compte : ouverture, débits, crédits, clôture et totaux de contrôle |
| Grand livre des tiers | Soldes commerciaux et historiques de paiement | Livre filtré par client ou fournisseur |
| Conditions de paiement | Un délai par facture | Modèles à plusieurs échéances, arrondi final, imputation des règlements sur les premières échéances ; balance âgée et prévision utilisent les échéances |
| Analyse par projet | Dépenses et liens projet, dimension disponible dans le schéma | Affectation lors d’un lien projet unique ; sélection dans l’écriture manuelle ; répartition par pourcentages avec conservation des centimes et de la contrepassation |
| Avoirs / débits hors retours | Avoirs issus d’un retour uniquement | Ajustements liés à la facture, TVA séparée, soldes clients/fournisseurs actualisés et annulation depuis l’origine |
| Retenues | Absentes du livre et des soldes | Enregistrement d’un justificatif déjà autorisé : bases, taux, codes, comptes, preuve ; imputation sur créances/dettes sans faux mouvement bancaire |
| Taxes datées | Date de début disponible | Date de fin ; contrôle lors de l’affectation d’une taxe à une ligne ; récapitulatif TVA calculé dans le livre après ajustements et contrepassations |
| Banque et rapprochement | CSV, rapprochement simple et groupé, avances clients présents | Conservés ; solde initial comptabilisé une fois ; protection des montants d’ouverture déjà comptabilisés ; paie intégrée aux mouvements de trésorerie |
| Paie | Paies validées et paiements dans RH | Coût employeur, net à payer et autres obligations dans le livre ; compte financier du paiement ; reprise explicite des paies configurées |
| Stock FIFO / coût moyen et frais d’approche | Déjà présents dans le sous-livre de valorisation | Comptabilisation explicite des valeurs enregistrées et liens uniques vers les écritures ; contrôle de contrepartie pour éviter de compter la facture et le stock deux fois |
| Immobilisations | Pas de registre | Registre lié à une acquisition déjà comptabilisée ; amortissement linéaire mensuel, ordre des mois, valeur résiduelle, dernier arrondi |
| Clôture | Clôture mensuelle | Transfert annuel du résultat, verrouillage des douze mois, refus de clôturer un exercice non terminé ; compte de résultat conserve les opérations historiques |
| Profil fiscal équatorien | Pays et identité générale | Personne physique par défaut ; régime et obligations non présumés ; preuve et date de confirmation ; contrôles du RUC et des obligations |
| Justificatifs fiscaux reçus | Données commerciales limitées | Métadonnées contrôlées par rapport aux bases et totaux des pièces existantes ; numéro, autorisation, identifiant, sustento, paiement, bases TVA et preuve de contrôle |
| ATS | Absent | Revue exportable et brouillon XML mensuel pour le sous-ensemble national documenté, testé contre le XSD SRI ; blocage des cas non couverts |
| Émission SRI | Adaptateur de facture ordinaire déjà préparé ; service réel non validé | Conservée ; aucune nouvelle capacité d’émission n’est annoncée et aucun document n’est marqué autorisé par les nouveaux enregistrements comptables |

## Ce qui reste hors du résultat prouvé

Cette livraison **ne constitue pas une parité intégrale avec Odoo ni une certification fiscale**. Les écarts suivants restent explicites :

- Positions fiscales automatiques appliquées aux produits et à la détermination des taxes ; les codes et taux saisis doivent être vérifiés selon l’activité et la date.
- Comptabilité et règlements multidevises avec gains/pertes de change. Le périmètre validé ici est USD, monnaie actuelle de cette entreprise.
- Émission électronique des notes de crédit/débit, retenues et guides de transport. Leur enregistrement comptable ne vaut pas émission ou autorisation SRI.
- ATS complet : RIMPE/semestriel, retenues, notes modificatives, retours, annulations, étranger, remboursements de frais et transactions spéciales. Ces cas bloquent l’export proposé ; ils ne sont pas omis silencieusement.
- Cession d’immobilisation, prorata et méthodes d’amortissement autres que linéaires ; calcul légal de paie/IESS, provisions et obligations annuelles spécifiques.
- Passage automatique de la valorisation stock au livre avec traitement complet des biens reçus non facturés et écarts de facturation. Le lien proposé exige une contrepartie contrôlée et une comptabilisation explicite.
- Présentation au SRI, obtention du RUC, certificat électronique, activation du service de signature, validation réelle en environnement de tests, puis émission en production.

Pour une personne physique, ne pas sélectionner « société » ni appliquer d’office les obligations de la Superintendencia de Compañías. Les obligations comptables, de retenue et d’ATS doivent venir du dossier du contribuable et des règles applicables, pas du choix de logiciel.

## Contrôles et fonctionnement

Les nouvelles commandes passent par `gama_accounting_ec`, façade publique `SECURITY INVOKER`. Le traitement privé vérifie session, autorisation du module, droit d’action et périmètre complet. Les nouvelles tables ont RLS, privilèges explicites et audit. Les écritures directes via Data API ne sont pas accordées. Une clé de commande est liée à l’acteur, à l’action et à la charge utile ; changer la requête avec la même clé est refusé.

Une facture comptabilisée ne peut plus changer de montant ; son annulation se fait dans son module d’origine. Une pièce ayant une écriture est conservée pour l’historique. Les écritures manuelles restent contrepassables. Le contrôle de période est partagé avec la clôture par un verrou mensuel.

Les modèles de conditions de paiement ne modifient pas les échéances historiques lors d’une modification du modèle. Un changement ultérieur de date de livraison décale les échéances déjà appliquées ; effacer cette livraison est refusé tant que son échéancier existe.

Le programme ATS est téléchargé uniquement lorsque l’opérateur demande un brouillon. Le démarrage conserve ses plafonds de taille et de requêtes.

## Vérifications reproductibles

- `npm run validate` : sources, types, liens de documentation, migrations historiques, tests de base isolée et cœur, fichiers générés et budgets de démarrage.
- `node --test tests/accounting-ecuador-db.test.cjs` : transactions métiers, contrepassations, livres, retenues, avoirs/débits, échéances, métadonnées fiscales, ouvertures, amortissements, paie, clôture, dates de taxes, droits et analyse par projet.
- `node --test tests/audit-valuation-db.test.cjs` : réceptions réelles et sorties FIFO/AVCO, frais d’approche, puis comptabilisation des valeurs dans le livre et refus de double comptabilisation.
- `node --test tests/accounting-ats.test.cjs` : structure ATS, regroupement, code de vente ATS 18 distinct du code SRI facture 01, validation XSD et refus des cas non couverts. Le test nécessite Python et `lxml` ; cette dépendance est déclarée en CI.
- Playwright : comptabilité, SRI, dossiers, retours et traductions. Les données sont simulées ou créées dans une base PGlite isolée, pas dans la base réelle.

## Références

- [Odoo Community 19.0 — manifeste l10n_ec](https://github.com/odoo/odoo/blob/19.0/addons/l10n_ec/__manifest__.py), [CSV des comptes](https://github.com/odoo/odoo/blob/19.0/addons/l10n_ec/data/template/account.account-ec.csv). Données existantes LGPL-3.0, attribution et licence dans `config/localizations/` ; aucun nouveau moteur Odoo n’est copié.
- [Odoo — documentation Équateur](https://www.odoo.com/documentation/19.0/applications/finance/fiscal_localizations/ecuador.html) : distinction entre localisation de base et modules EDI, ATS et guides.
- [SRI — formulaires et instructions](https://www.sri.gob.ec/formularios-e-instructivos1) ; programme ATS 1.19.0 publié le 23 septembre 2026 ; [XSD ATS](https://descargas.sri.gob.ec/download/anexos/ats/ats.xsd).
- [SRI — fiche technique ATS](https://www.sri.gob.ec/o/sri-portlet-biblioteca-alfresco-internet/descargar/72d717c2-88ed-47b7-baba-50b87b7198b7/Ficha%20Tecnica%20Transaccional%20Simplificado%20ATS.pdf).
- [SRI — modification des retenues au 1er mars 2026](https://www.sri.gob.ec/web/intersri/detalle-noticias?idnoticia=1273&marquesina=1).

## Enregistrement et déploiement

Point de contrôle du 3 octobre 2026, avant publication de l’interface :

| État | Preuve |
|---|---|
| Préparé | Sources, sorties compilées, guide utilisateur et comparaison détaillée dans cette branche |
| Enregistré | Premier commit local `92d3963` ; historique des migrations aligné sur les versions réellement retournées par Supabase |
| Testé | `npm run validate` : 167 tests réussis ; Playwright comptabilité/SRI/dossiers/retours : 67 tests réussis ; tests isolés, aucune pièce de test créée dans la base réelle |
| Base déployée | `20261003074945_accounting_ec_ledger` et `20261003075343_accounting_ec_fk_indexes`, application confirmée puis vérifiée par lecture |
| Interface | Publication GitHub en cours à ce point de contrôle ; consulter la PR et son déploiement pour l’état ultérieur |
| Fiscal réel | Aucun test SRI réel, aucune émission autorisée et aucun dépôt ATS |

Après les migrations : 14 factures de vente, zéro écriture comptable et un mois fermé, identiques aux comptages précédents. La façade refuse une requête sans session autorisée. Les nouvelles tables exposées ont RLS, lecture filtrée et aucun droit d’insertion direct pour `authenticated`. Le contrôle de sécurité ne signale pas de nouveau problème sur ces tables ; les avertissements antérieurs sur les tables privées et la [protection des mots de passe divulgués](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) restent distincts de cette livraison. Les 18 références de clés étrangères signalées sur les nouvelles tables ont reçu un index dans la migration complémentaire ; la migration déjà appliquée n’a pas été réécrite.
