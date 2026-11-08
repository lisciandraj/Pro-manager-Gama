# Finalisation Ventes et Comptabilité — 8 novembre 2026

Les écarts recensés dans la [matrice](features.csv) sont implémentés dans le
[contrat courant](../../docs/modules/sales-accounting-community.md). Les moyens
externes restent désactivés jusqu’à leur configuration sécurisée. Cette livraison
vise `development` ; aucune migration hébergée ni promotion de production n’est
réalisée.

## Parcours vérifiés

| Périmètre | Vérifications ciblées |
| --- | --- |
| Remises, frais, suggestions, copie et retours | Parcours SQL réels jusqu’aux écritures, transport exclu du retour, centimes cumulés et comptes figés ; UI mobile/bureau |
| Fidélité et valeur stockée | 11 tests SQL ; reçus réels, consommation, retours, remboursement mixte argent/portefeuille et droits |
| Factures autonomes | 12 tests SQL ; 7 remboursements après règlement ; facture sans commande, banque, SRI figé et reports ; E2E FR mobile/EN bureau |
| Escompte | 16 tests SQL et 6 cas navigateur ; trois traitements fiscaux, compensation des avoirs et taxes physiques composées |
| Moteur fiscal | 10 calculs et parcours facture/fournisseur/acompte ; sous-centimes, arrondi global, positions fiscales, rapports figés et confirmation d’un changement de règle |
| Comptes produits/catégories | 7 tests SQL et 3 parcours FR/EN/ES ; héritage indépendant, reset, conflit concurrent et droits |
| PDF enrichis | 4 tests unitaires, 6 SQL et 3 parcours navigateur ; vrais PDF relus, champs, annexes privées et gel des sélections |
| Signature | 7 tests SQL, portée native, 3 Edge et 4 parcours navigateur ; trois méthodes, réponse perdue, PDF altéré et commande unique |
| Paiements à distance | 10 tests SQL, 8 Edge, 3 parcours publics et 1 configuration ; HMAC, mode test sans argent, virement vérifié, réservations partagées et revue des litiges |
| Chiffre d’affaires | 8 tests SQL comparant mois/client/produit au grand livre ; avoirs, retours, contrepassations et reports |
| Régressions des écrans existants | 90 cas prioritaires et 14 cas supplémentaires de configuration/rapprochement |

Les captures sélectionnées figurent dans `clone-screens/`. Les tests utilisent des
bases locales jetables et des identités synthétiques. Les appels prestataires
sont remplacés uniquement dans les tests ; aucun paiement fictif n’est déclaré
réel dans l’application.

## Contrôles d’intégration

Sources, dépendances auditées, types, documentation, migrations, génération
reproductible et budget de démarrage sont contrôlés. Les scripts de première
installation de production restent liés à leur historique revu de 362 migrations
et excluent les ajouts de développement de cet historique figé. Les contrôles
vérifient son empreinte et l’exclusion des migrations ultérieures.

Une exécution locale complète de 905 cas pendant l’intégration avait 22 écarts
et deux cas PostgreSQL ignorés localement. Les écarts provenaient de migrations
encore modifiées en parallèle, de champs désormais obligatoires dans des fixtures
qui désactivent les triggers, d’attentes historiques et de trois vues du tableau
de bord privées d’autorisation de lecture. Ces points sont corrigés et leurs
fichiers revérifiés. La validation complète du commit livré et les deux scénarios
de concurrence PostgreSQL sont les contrôles GitHub de la PR ; ils restent des
conditions de fusion.

Après intégration de development (Contacts, palette et gel du bootstrap),
14 fichiers SQL fiscaux/achats/retours et 5 fichiers factures/escompte/remboursement
passent. Un scénario société/particulier lié conserve leurs identités financières
distinctes. Les 71 cas Contacts/bootstrap/promotion, 17 parcours navigateur ciblés
et 12 cas factures internes/outils passent aussi. La devise figée est vérifiée
à l’écran, dans le PDF et dans le texte copié, indépendamment de la société.

La validation complète GitHub du commit `a599b129` passe : 1 050 tests réussis,
zéro échec, deux cas réservés aux jobs PostgreSQL séparés. Ces jobs passent aussi.
Les contrôles navigateur ont ensuite révélé un clic Enregistrer ignoré pendant
le calcul fiscal et une attente sur une réponse périmée : corrections vérifiées
par trois tests asynchrones et 36 parcours de devis, plus neuf cas taxes/charges.
Les assertions de valeur de textarea et d’attente de sauvegarde ont été adaptées
au chargement différé sans modifier les attentes métier. Le commit final reste
soumis à tous les contrôles GitHub habituels.

Le test isolé de sauvegarde automatique simulait un chargeur sans fournir le
moteur fiscal désormais obligatoire. Il charge maintenant les vrais modules
fiscal et commercial avec des réponses RPC locales explicites : 11 tests de
sauvegarde et les 84 parcours quotidiens passent. Aucune garde produit n’est
rendue facultative. Le job de build dispose de 35 minutes pour conserver tous
les contrôles navigateur après une suite SQL/unitaire mesurée à 17,1 minutes ;
les budgets de démarrage de l’application sont conservés.

Les résultats détaillés et les commandes reproductibles sont dans
[verification.json](verification.json). La [première livraison](../../docs/history/odoo-community-first-delivery-2026-11-08.md)
est conservée séparément.
