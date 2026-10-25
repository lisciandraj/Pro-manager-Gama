# Affectation du résultat — référence 19.0

Source consultée le 25 octobre 2026 : [clôture annuelle Odoo 19.0](https://www.odoo.com/documentation/19.0/applications/finance/accounting/reporting/year_end.html).

Le résultat antérieur non affecté est une ligne calculée dans les livres de
l'exercice suivant. Les comptes de produits, charges et d'affectation ont une
ouverture annuelle nulle. Plusieurs comptes d'affectation sont possibles ;
ils apparaissent après le résultat dans le compte de résultat sans modifier
le bénéfice. Une OD explicite d'affectation utilise ces comptes et les comptes
de destination choisis. Aucune écriture automatique d'équilibrage ne remplace
cette décision.

## Intégration native prévue

Les rapports liront les écritures canoniques, leurs dates comptables et le mois
de début d'exercice existant. Les écritures historiques et les clôtures Coco
déjà validées seront conservées. Une ligne calculée portera un indicateur
explicite et des liens vers les mouvements qui l'expliquent ; elle ne sera
jamais enregistrée comme pièce validée.

Les comptes d'affectation utilisent le sous-type `equity_unaffected` déjà
disponible. Le passage entre ce sous-type et un compte ordinaire utilisé doit
être protégé pour éviter de modifier rétroactivement les ouvertures.

Scénarios indépendants : bénéfice de 100, affectation de 60 puis 40, perte de
30, plusieurs comptes d'affectation, contrepassation, exercice commençant en
juillet, dates verrouillées et lectures/export sans autorisation.

Statut : rapports natifs et contrôles serveur implémentés. Neuf tests de base
isolée réussissent ; neuf parcours navigateur ES/FR/EN × 390/768/1440 sont
préparés. H13 reste partiel jusqu’à leur validation.
