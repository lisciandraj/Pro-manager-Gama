# Écrans Coco

S12 réutilise ArcUI, GamaSales.modal, les champs Arc et les tableaux gaTable. Aucun logo, ressource, couleur ou composant Odoo n'est embarqué. Le bouton principal reste celui de Coco, orange et texte blanc. La grille utilise les bordures existantes, montants à droite et chiffres tabulaires ; le défilement se limite au tableau. Les fonctions nouvelles sont chargées à la demande via le manifeste des actifs.

Navigation : sept familles (Vue d'ensemble, Clients, Fournisseurs, Banque et caisse, Comptabilité, Rapports, Configuration) et raccourcis vers les sections historiques. Les liens existants gardent leurs identifiants. S12 comprend liste filtrée/paginée, formulaire, calcul sans mutation, détail, validation, comptabilisation, erreur de planification et annulation motivée. Un seul retour général reste dans l'en-tête commun ; le retour à la liste est une action locale.

FR/ES/EN : textes nouveaux choisis selon la langue de la session ; libellé de navigation dans le catalogue. Historique commun et portraits conservés. Un plan proposé par Agent Coco reste en brouillon ; son approbation est humaine. Les échéances exécutées par le traitement approuvé sont attribuées à Agent Coco et les messages correspondants restent en espagnol.

Preuves : `tests/accounting-plans.spec.js` à 390 et 1440 px dans chaque langue, avec calcul et écritures réels dans une base isolée, scan axe et captures CI. Les captures prouvent l'état montré ; elles ne prouvent pas toutes les tailles physiques ni un usage réel sur iPhone.
