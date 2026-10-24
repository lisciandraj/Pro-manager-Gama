# Plan de vérification

F01 : suites Ventes, factures, paiements, rapprochement et livres existantes. Elles couvrent les contrats de chaque étape ; leur réussite n'est pas une comparaison exhaustive sur instance Odoo.

F06–F08 : scénarios calculés indépendamment du moteur : assurance 1 200 sur douze mois = 100/mois ; 100 au prorata des 90 jours de janvier à mars 2026 = 34,44 / 31,11 / 34,45 ; 300 du 16 janvier au 28 février sur mois proportionnels = 102,13 / 197,87. Emprunt 1 200, douze mensualités à capital constant, taux nominal annuel 12 % : capital 100, intérêts du premier mois 12 et du dernier 1, total intérêts 78. L'annuité calculée est 106,62 avant ajustement final du capital.

Cas négatifs : NaN/Infinity, centime fractionnaire, taux/montants invalides, ligne déséquilibrée, source déjà consommée, pièce corrigée, période verrouillée, requête avec même clé et autre contenu, profil sans validation/export, appel anonyme, tentative d'approbation par Agent Coco et appel direct du planificateur.

F09 : le lot des échéances est annulé entièrement si une période ultérieure est fermée. Annuler un plan conserve les pièces et génère les contre-écritures à la date ouverte sélectionnée. La pièce source ne peut pas être corrigée avant annulation d'un plan actif.

Concurrence réelle : PostgreSQL 17 jetable, deux connexions authenticated. Deux créations sur la même source ne consomment pas deux fois sa capacité ; approbation rejouée avec même clé ; exécutions avec clés différentes ; annulations concurrentes. Le test refuse une URL distante ou une base non vide.

UI : création → calcul → brouillon sans écriture → validation → comptabilisation → détail de l'écriture → retour au plan. Six combinaisons FR/ES/EN × 390/1440, requêtes RPC réelles sur PGlite isolé, absence de débordement global, encodage de noms longs et caractères HTML, scan axe. Les suites comptables, historiques et modules connectés complètent les régressions.

Production : lectures uniquement des soldes, ACL, définitions, état du cron, version des actifs et numéro de migration. Aucune facture, banque, plan ou pièce fictive n'est créé en production.
