# Plan de vérification

F01 : `tests/accounting-sale-to-bank-db.test.cjs` restaure le schéma isolé, prépare uniquement les données de référence, puis passe toutes les transitions métier par les API publiques en rôle authenticated. Vente de deux unités à 50 USD, sans taxe dans ce scénario : facture interne de 100, écriture automatique unique, paiement de 100, import bancaire rejouable, rapprochement sans nouvelle écriture de trésorerie. Résultats indépendants : balance débit = crédit = 200 ; produit = 100 ; solde bancaire = 100 ; reste dû = 0 ; trésorerie et revenu du tableau de bord = 100. La seconde facturation des mêmes quantités est refusée. Les suites existantes couvrent les autres contrats ; leur réussite n'est pas une comparaison exhaustive sur instance Odoo.

F06–F08 : scénarios calculés indépendamment du moteur : assurance 1 200 sur douze mois = 100/mois ; 100 au prorata des 90 jours de janvier à mars 2026 = 34,44 / 31,11 / 34,45 ; 300 du 16 janvier au 28 février sur mois proportionnels = 102,13 / 197,87. Emprunt 1 200, douze mensualités à capital constant, taux nominal annuel 12 % : capital 100, intérêts du premier mois 12 et du dernier 1, total intérêts 78. L'annuité calculée est 106,62 avant ajustement final du capital. Une répartition de 0,03 sur six mois reste bornée à 0,03 sans reliquat négatif ; les mois à zéro ne génèrent pas de pièce. Un emprunt à 0 % comptabilise le principal sans ligne d'intérêt nulle.

Cas négatifs : NaN/Infinity, centime fractionnaire, taux/montants invalides, ligne déséquilibrée, source déjà consommée, pièce corrigée, période verrouillée, requête avec même clé et autre contenu, profil sans validation/export, appel anonyme, tentative d'approbation par Agent Coco et appel direct du planificateur.

F09 : le lot des échéances est annulé entièrement si une période ultérieure est fermée. Annuler un plan conserve les pièces et génère les contre-écritures à la date ouverte sélectionnée. La pièce source ne peut pas être corrigée avant annulation d'un plan actif.

Concurrence réelle : PostgreSQL 17 jetable, deux connexions authenticated. Deux créations sur la même source ne consomment pas deux fois sa capacité ; approbation rejouée avec même clé ; exécutions avec clés différentes ; annulations concurrentes. Le test refuse une URL distante ou une base non vide.

UI : création → calcul → brouillon sans écriture → validation → comptabilisation → détail de l'écriture → retour au plan. Neuf combinaisons FR/ES/EN × 390/768/1440, requêtes RPC réelles sur PGlite isolé, absence de débordement global, encodage de noms longs et caractères HTML, scan axe. Les suites comptables, historiques et modules connectés complètent les régressions.

Production : lectures uniquement des soldes, ACL, définitions, état du cron, version des actifs et numéro de migration. Aucune facture, banque, plan ou pièce fictive n'est créé en production.

## Configuration et correspondance CSV

`accounting-configuration-db.test.cjs` vérifie les 18 types, le hors bilan,
les groupes créés dans les deux ordres, les préfixes invalides, les soldes
d'ouverture, la pagination et l'instantané des exports. Les séquences sont
testées par année, mois et exercice décalé ; une validation échouée ne consomme
pas de numéro, les références ERP et leur recherche restent utilisables.

Les dates globales, ventes, achats, taxes et définitives sont contrôlées côté
serveur, y compris pour une ligne de taxe sans `tax_id`. Les scénarios couvrent
les exceptions personnelles/globales, révocations, expirations, version de date,
raison obligatoire et refus des propositions IA non approuvées. Auth, périmètre,
droits de mutation/export et accès direct aux tables sont vérifiés séparément.

Résultats indépendants : produit antérieur 100 puis produit de période 30 →
ouverture -100, crédit 30, clôture -130. Exercice débutant en juillet → juin 2026
appartient à 2025 et juillet à 2026. Verrouillage au 31 mai → date comptable du
15 mai reportée au 1er juin, avec preuve de la date demandée.

Le test PostgreSQL 17 ajoute deux validations simultanées dont les formats de
journaux peuvent produire le même numéro, puis une course verrouillage/validation.
Les deux numéros sont distincts et la validation se situe entièrement avant ou
après la modification du verrouillage. Le contrôle est réellement concurrent,
sur deux connexions authenticated ; le SKIP local ne constitue pas sa preuve.

Les neuf parcours UI `accounting-configuration.spec.js` utilisent les RPC réelles
en base isolée : compte → séquence → verrouillage → lecture de l'écriture →
groupes → balance → grand livre → historique. La création de l'écriture de
100 USD passe par l'API publique du test ; elle n'est pas présentée comme une
saisie UI. L'import de 19,25 USD avec colonnes inconnues est bloqué en présence
d'une date impossible, puis réussi et rejoué sans doublon ni écriture de cash.
FR/ES/EN × 390/768/1440, absence de débordement et scans axe complètent le parcours.

## Moyens nommés et reliquats datés

`accounting-partial-matching-db.test.cjs` utilise les calculs indépendants de [partial-matching.md](partial-matching.md), contrôle les préférences et noms figés, les dates, fournisseurs, frais signés, avances et autorisations. `accounting-payment-upgrade-db.test.cjs` applique les migrations sur une base déjà peuplée et compare les empreintes ; il vérifie ensuite l'annulation et le rejeu d'un rapprochement antérieur. `accounting-partial-matching.spec.js` exécute le parcours préférence → paiement → banque 40 puis 60 → aperçu → annulation du premier groupe, dans neuf combinaisons de langue et de largeur. La suite de concurrence ajoute une course de deux paiements sur une seule ligne bancaire de 150 ; une seule portion de 100 est acceptée, puis seulement les 50 restants.
