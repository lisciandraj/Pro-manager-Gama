# Reprise des trois chantiers · 28 octobre 2026

Cette livraison poursuit Comptabilité, TMS et Espace de travail. Elle ne clôt pas les matrices Odoo, OptimoRoute et Macro : leurs fonctions partielles restent détaillées dans les matrices respectives. L’émission SRI demeure hors périmètre.

## Fonctions livrées

| Axe | Parcours | Garanties et limites |
| --- | --- | --- |
| Comptabilité | Contrôles → Cycle des immobilisations → Plan : linéaire, dégressif ou dégressif puis linéaire, avec facteur mensuel explicite et prorata du premier mois. Le plan calculé se consulte en rouvrant Plan. | Calcul PostgreSQL NUMERIC, centime final exact, valeur résiduelle préservée, paramétrage humain, reçu d’idempotence et protection contre un formulaire périmé. Enregistrer le plan ne comptabilise rien. Le moteur de comptabilisation existant et ses périodes verrouillées restent utilisés. Un plan déjà comptabilisé ne peut pas changer de méthode. |
| TMS | Planning avancé → Analyse : kilomètres GPS observés, minutes observées et segments exclus. | Somme de segments directs entre points consécutifs. Précision de chaque point ≤ 50 m, intervalle > 0 et ≤ 300 s, vitesse calculée ≤ 130 km/h. Aucune interpolation au-dessus d’une coupure. Une absence de segment exploitable vaut « — », un trajet stationnaire exploitable vaut zéro. Ce n’est ni le kilométrage routier total ni une preuve de couverture complète. |
| Espace collaboratif | Agenda : tâches Projets et activités CRM ouvertes affectées au demandeur, période de 93 jours au plus, pagination, détail et ouverture dans le module source. | Façade SECURITY INVOKER, RLS et droits des modules sources inchangés. Les dates des tâches restent civiles ; les activités sont sélectionnées et affichées dans le fuseau ERP. Ni création d’événement, ni réservation, ni synchronisation de compte externe. |

Pour le dégressif, chaque mois applique le facteur au capital amortissable restant. La méthode mixte retient au minimum le montant linéaire du restant sur les périodes pondérées encore à courir ; une fois la bascule effectuée, le montant reste constant à l’arrondi près. La dernière échéance absorbe le solde. Exemple : base de 900, cinq mois, facteur 0,4 → 360 / 216 / 129,60 / 77,76 / 116,64 ; mixte → 360 / 216 / 129,60 / 97,20 / 97,20. La périodicité de ce moteur natif est mensuelle, le facteur n’est pas un taux annuel.

Référence fonctionnelle consultée le 28 octobre : [méthodes d’amortissement Odoo 19](https://www.odoo.com/documentation/19.0/applications/finance/accounting/vendor_bills/assets.html). Implémentation originale, aucun code Odoo utilisé.

## Vérification et mise en production

Migration additive `20261028175918_coco_three_workstreams.sql` : trois attributs de politique sur les immobilisations, deux helpers privés sans droit d’appel client et une façade de lecture d’agenda. Aucun échéancier historique n’est recalculé, aucune facture ni écriture ni position GPS n’est créée par la migration. L’absence de réglage prorata historique reste inconnue (`null`). Les contrats RPC antérieurs sont conservés ; les anciennes requêtes réutilisent le paramétrage courant.

- `tests/three-workstreams-db.test.cjs` : mise à niveau d’une base peuplée, empreintes inchangées sur les colonnes antérieures et l’historique, calculs exacts et prorata, refus des facteurs invalides, appel IA non approuvé, plan verrouillé, trous GPS, absence/valeur zéro, pagination, dates Quito et confidentialité.
- Régressions serveur : `accounting-audit-db`, `tms-pro-db`, `workhub-db`.
- Parcours navigateur : `accounting-audit.spec.js`, `tms-pro.spec.js`, `workhub.spec.js`, nouveaux cas aux largeurs 390 et 1440, changements FR/ES/EN ; contrôles d’accessibilité sur l’agenda et l’analyse TMS.
- Contrôles communs, génération reproductible et budgets existants avant fusion. Les gates CI restent inchangés.
- Avant installation : vérifier les définitions des deux fonctions patchées et les colonnes existantes ; conserver les définitions antérieures et comparer les empreintes privées des données historiques avant/après. L’installation est une opération de schéma uniquement, enregistrée dans le registre des migrations.
- Après publication : vérifier le commit dans `coco-build.json`, l’attribut HTML et les trois actifs servis. La recette navigateur utilise des bases isolées, pas de données de test en production.

Le statut et les liens CI de publication sont consignés dans la pull request de cette livraison pour éviter de relancer une publication uniquement pour mettre à jour ce document.

## Ce qui reste ouvert

- Comptabilité : différés d’avoirs et de factures à plusieurs comptes, modèles/groupes d’immobilisations, fonctions fiscales et analytiques avancées, autres écarts de la matrice de 108 points. Aucune conformité ou parité complète annoncée.
- TMS : kilométrage routier complet, collecte mobile en arrière-plan, trafic/routage avancé, notifications automatiques avec prestataire et recette terrain. Le départ différé proposé depuis une attente vérifiée est déjà arrivé dans `main` par la PR #264 et est conservé.
- Collaboratif : boîte mail complète, synchronisation Google/Outlook, réservation et appels/transcription. Ils exigent des choix d’intégration et des accès propres à Coco. Aucun compte créé, aucun service payant activé, aucun mail envoyé par cette livraison. Le tableur/canvas et les agents MCP restent des chantiers distincts.
