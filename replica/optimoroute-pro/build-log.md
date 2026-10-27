# Construction et vérification

27 octobre 2026. S01 : parcours TMS et interface Coco conservés. S02–S04 : calendrier et aperçu/apply avec versions et empreinte ; règles livraison et ressources ; trois fenêtres intégrées au moteur natif et à l'horaire vérifié. S05–S06 : GPS explicite, traces et ETA réévaluée ; arrêter au masquage de page ou à la déconnexion. S07 : avis unique par jeton expirant après réception complète. S08 : indicateurs et exports CSV/GPX.

Les écrans sont construits dans `src/features/transport/pro-workspace.js`, l'API dans la migration `tms_pro_planning_tracking`, le partage de position dans `gps.js`. Les copies racine sont générées par le build. Aucun service externe nouveau ni compte OptimoRoute n'est utilisé.

Les points partiels et absents figurent dans `features.csv`. Ce lot ne constitue pas une certification d'équivalence intégrale à OptimoRoute Pro. L'optimisation reste native, les notifications gardent le mode manuel existant et la PWA reste limitée au premier plan. Les captures S02/S05 témoignent de l'interface Coco ; aucune comparaison visuelle au produit authentifié n'est revendiquée.
