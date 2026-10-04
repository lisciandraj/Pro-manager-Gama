# Dashboard : vues, filtres et analyses

Le Dashboard conserve ses agrégations serveur et ses droits de lecture. Une période commune contrôle les indicateurs et les graphiques ; les soldes, stocks et priorités sont actuels et portent leur périmètre explicitement. Les quatre indicateurs d’accueil déjà personnalisables gardent leur propre périmètre mensuel.

Les périodes incluent aujourd’hui, semaine en cours (lundi), mois, mois précédent, trimestre, 30 ou 90 jours, année et dates personnalisées. Les dates relatives utilisent le fuseau de l’entreprise.

Le filtre Activité s’applique aux indicateurs, cartes de modules, panneaux financiers, coûts RH et priorités de l’activité. Personnaliser permet de masquer des panneaux et des sources. Les vues favorites enregistrent période, vue métier, activité, panneaux, sources et type de graphique ; les périodes relatives sont recalculées lorsqu’on applique une favorite. Dix vues au maximum, noms limités à 80 caractères. Les vues sont propres au compte vérifié par le serveur et à ce navigateur : elles ne se synchronisent pas entre appareils. Seules ces préférences sont stockées localement, jamais les résultats métier.

Le graphique facturation/cobros propose barres ou courbes, agrandissement, tableau exact et CSV. Un clic ou la touche Entrée/Espace sur un point sélectionne sa période pour l’ensemble du Dashboard. Les liens des indicateurs et priorités ouvrent les dossiers existants.

L’export CSV des indicateurs respecte les sources visibles, les droits d’export et les sources réellement disponibles. Il inclut dates, unité/devise et portée actuelle ou période. Les sources indisponibles ne deviennent pas des zéros. Les exports du graphique conservent ses montants TTC, les CSV neutralisent les chaînes interprétables comme formules. Les valeurs sont exportées dans leur monnaie d’origine.

Inspiration fonctionnelle : documentation officielle [Odoo Dashboards](https://www.odoo.com/documentation/19.0/applications/productivity/dashboards.html), filtres globaux, favorites et outils de graphique. Coco ne reproduit pas l’éditeur Spreadsheet d’Odoo.
