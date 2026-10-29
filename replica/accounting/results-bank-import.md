# Relevés au grand livre et journaux — vérification

Lot de la [PR 249](https://github.com/lisciandraj/Pro-manager-Gama/pull/249), repris le 27 octobre 2026. Référence fonctionnelle inchangée : Odoo 19.0 Enterprise ; composants, authentification, documents et infrastructure Coco conservés. [Règles et parcours](bank-import-ledger.md).

## Preuves métier

Un import de 100 USD crée débit banque 100 / crédit transitoire 100. Les rapprochements successifs de 40 et 60 consomment uniquement leurs portions. Annuler le premier remet 40 en attente ; le second reste actif. Les trois traitements de paiement, les décaissements fournisseurs, les flux opposés et les frais de 3 sur un encaissement brut de 100 sont vérifiés indépendamment des montants calculés par l’interface. Un réimport du même fichier ne génère aucune autre pièce. Les dates bancaires restent distinctes, et un import contenant une date verrouillée est intégralement annulé.

Les lectures et écritures passent par des façades invocatrices et des contrôles privés Auth, MFA, module, périmètre et droits. Les sources comptabilisées sont immuables ; les anciennes lignes non comptabilisées gardent leurs règles antérieures. Une reprise avec ancien rapprochement est refusée, même si ce rapprochement a été annulé. La revue parcourt plus de 200 lignes avec sélection interpages bornée à 200 par opération. Le lien d’historique résout la référence de l’écriture réelle.

Les listes de journaux paginées partagent les critères des cartes ; les totaux portent sur toutes les lignes filtrées. L’export compare une empreinte à chaque page et à la fin. Le test indépendant utilise 61 écritures de 2,50, soit 152,50, et un brouillon distinct. Les lectures n’inventent pas de valeur lorsqu’aucune pièce n’existe.

## Données réelles avant migration

Lecture seule du 27 octobre : **58 écritures, 138 lignes, débit = crédit = 8 552,49 USD, zéro écriture déséquilibrée**. Les 89 mouvements bancaires et 26 groupes sont conservés. Les [23 empreintes de départ](evidence/bank-import-before.json) sont identiques [après installation](evidence/bank-import-after.json), avec [le même contrôle](verify-bank-import-snapshot.sql).

Sauvegarde logique privée de ces 23 tables et des quatre fonctions remplacées : **1 181 142 octets**, SHA-256 `f465376662b5536b45b473195d44c59bab563e315b83e386b15b9a4cc6c571a8`. Aucun export privé n’est dans le dépôt. Cette sauvegarde ciblée ne prouve ni un PITR ni une restauration intégrale du projet ; ceux-ci restent nécessaires avant une reprise structurelle.

Les **526 comptes historiques ne possèdent aucun sous-type détaillé**. Aucun compte transitoire admissible ni méthode bancaire nouvelle n’est configuré. L’interface explique qu’il faut créer ou classer un compte dans Types et comptes avant l’activation. Le lot ne choisit aucun compte ni date de reprise à la place de l’entreprise.

## Couverture et suite

La matrice conserve **108 lignes : 54 testées, 30 partielles, 20 à développer, 3 bloquées et SRI exclu**. Le diagnostic Replica indique 53 exigences obligatoires incomplètes sur les 107 incluses. Les contrôles de ce lot démontrent ses scénarios, sans valider l’intégralité de F12, A02 ou G04.

F12 reste partiel : reprise des anciens groupes à préparer ; les paiements directement comptabilisés en banque apparaissent provisoirement avec le mouvement importé avant leur compensation au rapprochement. Stock Odoo 19, taxes avancées, analytique/budgets, immobilisations avancées, multi-sociétés, consolidation, formats bancaires et services connectés restent explicitement ouverts dans [la matrice](features.csv). Aucun solde d’équilibrage ni opération réelle de test ne doit être créé pour les masquer.

## Retour arrière

Conserver le schéma additif, les politiques et les pièces utilisées. Un retour de l’interface exige une reconstruction et une publication contrôlées ; il ne supprime aucune écriture. Si l’import présente un défaut après activation, suspendre les imports de la banque concernée et corriger en avant. Ne pas décomptabiliser les relevés ni supprimer les métadonnées pour retrouver artificiellement le traitement antérieur.

## Installation et validation

Migrations installées le 27 octobre 2026, à 11:28 UTC : `20261027112820_accounting_bank_import_ledger` et `20261027112825_accounting_journal_dashboard`. Les octets enregistrés par Supabase correspondent exactement aux fichiers de `supabase/migrations/` et aux archives de `supabase/sql/applied/` (**22 950** et **5 882** octets). Le registre local contrôle 285 migrations appliquées. Aucun paramètre métier n’a été activé.

[Vérification de production](evidence/bank-import-production.json) : deux tables privées avec RLS sans droit direct client ; deux façades invocatrices refusées à `anon` ; quatre auxiliaires non exécutables directement ; déclencheurs d’immuabilité, capture et historique actifs. Une transaction SQL en lecture seule, sous le rôle `authenticated` et l’identité d’un administrateur existant avec AAL1, lit cinq journaux, 58 écritures et les mêmes totaux débit/crédit. Ce contrôle SQL ne remplace pas un parcours navigateur connecté. Les [appels HTTP anonymes](evidence/bank-import-anonymous.json) sont refusés avec HTTP 401 / `42501`.

La [CI comptable 40496922600](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40496922600) du commit `362bbd3353fc02bb39db9d5e1c8592dce8fee68f` réussit **106 parcours navigateur** et la concurrence réelle PostgreSQL. Les neuf nouveaux parcours couvrent les trois langues et les largeurs 390/768/1440, dont la sélection sur plusieurs pages. Les captures et traces sont dans [l’artefact de cette exécution](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40496922600/artifacts/12730757663), dont [les journaux sur ordinateur](evidence/accounting-journals-fr-1440.png) et [la configuration sur téléphone](evidence/accounting-bank-policy-fr-390.png), avec données isolées. Les contrôles ciblés import/journaux comptent **16 tests réussis**, plus la reprise peuplée. Celle-ci vérifie la conservation des anciennes pièces, des rapprochements et de leur annulation.

La [construction 40496922673](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40496922673) est réussie : **640 tests unitaires, 638 réussis, deux contrôles PostgreSQL exécutés dans leurs jobs séparés, aucun échec**. Les parcours suivants passent aussi : 52 Agent/comptabilité, 42 TMS, 80 historiques/dossiers et 27 accès/chargement. Ces nombres concernent des suites distinctes pouvant se recouper ; ils ne constituent pas un score de parité.

Les [12 workflows de la PR](evidence/bank-import-ci.json) ont tous réussi, ainsi que les [102 scénarios responsive sur le commit fusionné](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40499366493). La dernière vérification SQL à 12:01 UTC conserve les 23 empreintes, 58 écritures, 138 lignes et 8 552,49 USD de chaque côté.

Deux avertissements de sécurité Supabase préexistaient : [fonction administrative `coco_admin_security_review` en SECURITY DEFINER](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable) et [protection des mots de passe compromis désactivée](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Aucun nouvel avertissement de sécurité ; les deux nouvelles tables privées expliquent les deux informations RLS sans politique. L’index ajouté réduit les clés étrangères non indexées de 38 à 37 ; les 203 avertissements de performance RLS existants restent suivis séparément.

La [PR 249](https://github.com/lisciandraj/Pro-manager-Gama/pull/249) est intégrée dans `main` au commit `0263cb443cc7917e160e4e1f76e6b04bcf9c75f1`. Le processus Pages produit `coco-build.json` avec le commit intégré ; [verify-web.py](verify-web.py) compare ce commit et dix fichiers de production aux octets Git. L’installation SQL et la publication de l’interface sont deux preuves distinctes. Le navigateur de production est déconnecté : les tests isolés ne doivent pas être présentés comme des tests connectés de production.

**Publication vérifiée le 27 octobre à 12:08 UTC** : le [manifeste et les dix fichiers servis](evidence/bank-import-web.json) correspondent exactement à `0263cb443cc7917e160e4e1f76e6b04bcf9c75f1`, sur [Coco ERP](https://lisciandraj.github.io/Pro-manager-Gama/). Les [dix workflows déclenchés sur main](evidence/bank-import-main-ci.json) réussissent, dont 106 parcours comptables et 102 responsive. Le navigateur recharge normalement l’écran de connexion ; aucun compte ni opération de test n’a été créé en production. Le contrôle des écrans connectés reste non réalisé.

La préparation de la suite stock est documentée dans [stock-transition-19.md](stock-transition-19.md). Elle conserve explicitement 1 756 produits sans valorisation configurée et 39 mouvements sans coût antérieurs au suivi historique ; aucune écriture ou estimation de reprise n’est créée par cet audit.
