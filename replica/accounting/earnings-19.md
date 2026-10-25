# Affectation du résultat — référence 19.0

Source consultée le 25 octobre 2026 : [clôture annuelle Odoo 19.0](https://www.odoo.com/documentation/19.0/applications/finance/accounting/reporting/year_end.html).

Le résultat antérieur non affecté est une ligne calculée dans les livres de
l'exercice suivant. Les comptes de produits, charges et d'affectation ont une
ouverture annuelle nulle. Plusieurs comptes d'affectation sont possibles ;
ils apparaissent après le résultat dans le compte de résultat sans modifier
le bénéfice. Une OD explicite d'affectation utilise ces comptes et les comptes
de destination choisis. Aucune écriture automatique d'équilibrage ne remplace
cette décision.

## Intégration native

Les rapports lisent les écritures canoniques, leurs dates comptables et le mois
de début d'exercice existant. Les écritures historiques et les clôtures Coco
déjà validées sont conservées. Une ligne calculée porte un indicateur
explicite et des liens vers les mouvements qui l'expliquent ; elle n’est
jamais enregistrée comme pièce validée.

Les comptes d'affectation utilisent le sous-type `equity_unaffected` déjà
disponible. Le passage entre ce sous-type et un compte ordinaire utilisé doit
être protégé pour éviter de modifier rétroactivement les ouvertures.

Scénarios indépendants : bénéfice de 100, affectation de 60 puis 40, perte de
30, plusieurs comptes d'affectation, contrepassation, exercice commençant en
juillet, dates verrouillées et lectures/export sans autorisation.

Statut : H13 testé dans les environnements isolés. Treize tests serveur et
neuf parcours navigateur ES/FR/EN × 390/768/1440 réussissent. La concurrence
PostgreSQL 17 vérifie deux clôtures simultanées. Le commit `75e601cb` passe
les douze workflows, dont 88 tests du parcours comptable et 173 tests
transversaux d’architecture. Les [preuves](results-earnings-19.md) distinguent
ces validations de la navigation authentifiée en production, non attestée.

Les rapports existants excluent aussi les comptes d’affectation du bilan et affichent le résultat non affecté. Avec cette configuration, la clôture annuelle exige une affectation complète, conserve le bénéfice dans le compte de résultat et verrouille les douze mois sans seconde écriture de transfert. Les contrôles et justificatifs de clôture existants restent obligatoires. Sans compte d’affectation configuré, le fonctionnement historique est conservé.
