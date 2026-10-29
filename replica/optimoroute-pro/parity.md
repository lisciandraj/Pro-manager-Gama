## Parity: 91.6 / 100

features 91.6  (37 counted, must-haves 24 of 24 done)

## By area, weakest first
- Analyse                       75.0  (2 features)
- Intégration                   75.0  (2 features)
- Planning                      84.6  (5 features)
- Client                        87.5  (3 features)
- Ressources                    88.9  (5 features)
- Calendrier                    90.9  (4 features)
- Conducteur                    90.9  (4 features)
- Contraintes                  100.0  (6 features)
- Dispatch                     100.0  (1 features)
- Suivi                        100.0  (4 features)
- Exports                      100.0  (1 features)

## Missing, in build order
- [should] Analyse: Analytics prévu et réalisé, partial  (OTIF et écarts d’arrivée ; somme partielle des segments GPS filtrés, minutes observées et segments exclus. Pas de kilométrage routier réel complet.)
- [should] Calendrier: Commandes ou visites récurrentes, partial  (Modèles de tournée existants et récurrence commerciale; pas de tâches terrain autonomes)
- [should] Client: Notifications SMS et email automatiques, partial  (Préparation SMS/WhatsApp existante; envoi manuel conservé et aucun fournisseur activé)
- [should] Conducteur: GPS mobile en arrière-plan, partial  (La PWA arrête le partage lorsque la page est masquée)
- [should] Intégration: Import de commandes à livrer, partial  (Par les commandes et la préparation Coco; aucune livraison détachée du stock)
- [should] Planning: Temps routiers et itinéraire optimisé sur route, partial  (Tracé OSRM facultatif dans l’ordre Coco; temps vérifiés réutilisés et repli estimé; pas de réoptimisation mondiale des temps routiers)
- [should] Planning: Équilibrer les arrêts ou le temps, partial  (Heuristique native; pas une équivalence de son algorithme propriétaire)
- [could] Ressources: Début de journée flexible automatique, no  (Horaires fixes et proposition manuelle fondée sur l’attente initiale; optimisation automatique globale encore absente)

## Left out on purpose (not scored)
- Réimporter les contacts et données propriétaires: Données de GAMA uniquement
- Routage poids lourds dangereux et nuitées: Fonctions de l'offre Custom hors Pro


Ce score est une auto-évaluation de la matrice délimitée ci-dessus, pas une certification de copie intégrale. Aucune comparaison visuelle à un compte authentifié du produit de référence n’a été réalisée. Les fonctions partielles et absentes restent à compléter.
