# Architecture et intégration

Réutiliser les comptes, journaux, écritures, lignes et tiers existants. Ne pas créer de second livre ni de deuxième authentification. Monnaie société inchangée ; `numeric` PostgreSQL pour les calculs ; `date` pour les dates comptables, `timestamptz` pour la technique.

`gama_accounting_plans` est une façade invocateur, avec traitement privé contrôlé (Auth, MFA, module, scope, droits métier et export). Les tables privées `accounting_plans` et `accounting_plan_items` ont RLS et aucun accès Data API direct. Ce choix reprend le contrat du module comptable existant ; les fonctions privilégiées ont un search_path vide et un EXECUTE explicitement restreint.

Un plan commence en brouillon. Sa validation nécessite une personne autorisée. Chaque occurrence possède un UUID stable, une date, des lignes et un lien vers l'écriture créée par `gama_accounting_book`, donc les mêmes contrôles de période, comptes et partie double. Un verrou sur le plan sérialise validation, exécution et annulation. La clé de requête est liée à l'acteur, l'action et la charge utile ; l'unicité par occurrence protège les exécutions depuis deux clés différentes.

Différés : lien obligatoire vers une ligne de charge ou de produit validée, contrôle de la capacité disponible sous verrou de cette ligne. Reclassement unique à la validation, reconnaissance en fin de mois. Jours inclusifs, mois proportionnels au nombre de jours du mois et mois complets sont décrits dans [grouped-deferrals.md](grouped-deferrals.md), avec les clôtures groupées et leurs extournes.

La configuration privée `accounting_invoice_deferral_settings` ajoute, séparément pour charges et produits, journal, compte de report, calcul et mode. Les dates des lignes de vente et la ventilation nette des factures fournisseurs alimentent le même moteur dans la transaction de validation. Les références `invoice_id`/`supplier_invoice_id` et `invoice_line_key` relient les pièces et protègent l'unicité. Le mode individuel approuve l'automatisation existante lors de la validation humaine ; le mode groupé rejoint la revue de clôture. Aucun historique n'est rejoué et aucun réglage n'est inventé. Voir [invoice-deferrals.md](invoice-deferrals.md).

Emprunts : lien vers la ligne de dette déjà constatée, sans création d'encaissement fictif. Échéancier saisi/importé ou calcul à principal constant ou annuité. Chaque échéance débite la dette longue et les intérêts, crédite la dette courte, reclasse le principal des douze mois suivants et programme son extourne le lendemain. Le règlement bancaire reste distinct. L'annulation conserve les pièces et génère des contre-écritures à une date ouverte, sans effacer le passé.

Récurrences : modèle de lignes non bancaires équilibrées ; fréquence mensuelle ancrée à la date de départ (31 janvier → fin février → 31 mars). Les paiements, taxes et lettrages nécessitent leurs parcours dédiés, ils ne sont pas inventés par un modèle OD.

| Action RPC | Droit | Résultat |
| --- | --- | --- |
| list / detail / context | view, scope all | Plans paginés et liens aux pièces |
| preview | create | Calcul sans écriture |
| save | create | Plan en brouillon |
| activate | validate | Plan approuvé ; reclassement du différé |
| post_due | validate | Comptabilisation atomique des échéances dues |
| cancel | validate | Annulation motivée et contre-écritures datées |
| list + export | export | Toutes les pages sélectionnées |

La capture d'historique des plans est enregistrée avant toute utilisation. Les écritures conservent leur capture actuelle ; les actions Agent Coco gardent leur provenance, les validations UI leur auteur humain et son portrait déjà disponible.

Les nouvelles vues se chargent à la demande. ArcUI, GamaSales.modal, gaTable/gaScroll, tokens `--arc-*`, boutons orange et textes blancs ; pas de nouveaux composants de marque. Sept familles de navigation donnent accès aux sections compatibles existantes. Historique commun à droite inchangé dans son contrat. Les historiques de plans et de pièces ouvrent leur dossier précis ; le détail d'une écriture permet de revenir au plan lié.

Le traitement pg_cron `coco-accounting-plans` s'exécute chaque heure à la minute 15. Aucun plan n'est automatique par défaut. La validation humaine avec MFA si requis approuve ce choix pour ce plan immuable. Le traitement serveur recontrôle le compte actif, les droits et la politique MFA à chaque tentative, sans fabriquer de niveau aal2. Un changement de droits ou une exigence MFA qui ne peut pas être satisfaite suspend la comptabilisation et laisse une erreur visible dans le dossier. Les tentatives sont techniques et ne produisent pas de faux événements métier d'échec. Chaque passage prend au plus 250 plans, sous verrou SKIP LOCKED. L'échéancier et ses pièces restent atomiques.

Étapes restantes : voir la matrice. La migration ne modifie ni les montants existants, ni le stock, ni les périodes, ni SRI. Toute conversion multi-sociétés et toute modification de politique du stock exigent leur propre reprise ; elles ne sont pas activées par cette extension.

La suite native de paramétrage et de correspondance CSV est décrite dans [configuration.md](configuration.md), avec les règles de numérotation, de dates, les protections de concurrence et les écarts conservés.

La suite banque/attente et les cartes de journaux réutilisent le même livre et les groupes existants : voir [architecture du lot](bank-import-ledger.md).
