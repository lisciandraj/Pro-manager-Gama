# Construction et vérification

27 octobre 2026. S01 : parcours TMS et interface Coco conservés. S02–S04 : calendrier et aperçu/apply avec versions et empreinte ; règles livraison et ressources ; trois fenêtres intégrées au moteur natif et à l'horaire vérifié. S05–S06 : GPS explicite, traces et ETA réévaluée ; arrêter au masquage de page ou à la déconnexion. S07 : avis unique par jeton expirant après réception complète. S08 : indicateurs et exports CSV/GPX.

Les écrans sont construits dans `src/features/transport/pro-workspace.js`, l'API dans la migration `tms_pro_planning_tracking`, le partage de position dans `gps.js`. Les copies racine sont générées par le build. Aucun service externe nouveau ni compte OptimoRoute n'est utilisé.

Les points partiels et absents figurent dans `features.csv`. Ce lot ne constitue pas une certification d'équivalence intégrale à OptimoRoute Pro. L'optimisation reste native, les notifications gardent le mode manuel existant et la PWA reste limitée au premier plan. Les captures S02/S05 témoignent de l'interface Coco ; aucune comparaison visuelle au produit authentifié n'est revendiquée.


- S03/S04/S05 · 2026-10-27 · Capacités personnalisées, éditeurs de ressources et de charges, départ/retour par conducteur, instantanés de tournée et navigation aux bons lieux. Charge inconnue bloquante. Compatibilité des requêtes anciennes préservée.
- S02/S06 · 2026-10-27 · Carte et horaires vérifiés par occurrence du dépôt ; CSV enrichi des charges et GPX des deux extrémités. Les tournées historiques et leurs contrôles restent conservés.
- Restent hors parité intégrale : optimisation routière avancée, envoi automatique de notifications, récurrence de tâches autonomes, GPS natif en arrière-plan et démarrage flexible automatique.

- Intégration de #258 : actualisation de carte, positions récentes, routes colorées et tracé routier facultatif conservés. Les coordonnées de départ/fin viennent de l’instantané ; aucune arrivée générale ajoutée aux fins ouvertes. 59 parcours navigateur et 24 contrôles d’architecture réussis.
