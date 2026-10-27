# Architecture native TMS

Conserver JavaScript modulaire statique, manifeste d’actifs, Supabase/PostgreSQL et Auth, Flotte/RH, commandes et moteur de préparation. Aucun nouveau service payant. Les dates commerciales utilisent le fuseau ERP (America/Guayaquil), les positions et événements utilisent timestamptz.

Les tables additionnelles sont dans private, avec RLS et révocation des accès directs. La façade publique gama_tms_pro est SECURITY INVOKER ; l’implémentation privée contrôle auth, MFA, périmètre conducteur/dispatch et permission d’action avant chaque opération. La façade anonyme d’avis ne reçoit qu’un jeton aléatoire de suivi, vérifie expiration et livraison effectuée, et ne remplace jamais un avis existant. Les médias et encaissements restent dans les circuits existants.

| Commande | Droits | Parcours |
| --- | --- | --- |
| overview / rules / resources | dispatch read | F02/F03 |
| rules_save / driver_save / vehicle_save / settings_save | dispatch edit + versions | F02/F03 |
| preview / plan_range | dispatch edit + create, empreinte et clé de requête | F02 |
| live / analytics / export | dispatch read, export exige export | F04/F06 |
| position | chauffeur affecté, tournée partie, edit | F04 |
| feedback | jeton public valide, livraison terminée, insertion unique | F05 |

La planification du jour conserve les verrous, indisponibilités RH/Flotte, capacité poids/volume, promesse initiale, tournées manuelles/parties et reçus existants. Les règles additionnelles filtrent les candidats, calculent le prochain des trois créneaux admissibles et configurent les horaires du conducteur. Les modes équilibrés restent des heuristiques documentées ; les kilomètres inconnus restent estimés. Le planning de période déplace uniquement les livraisons liées à une commande, non parties et sans tournée protégée ; il ne crée ni commande récurrente ni sortie de stock.

Les positions sont attachées au compte vérifié et à la tournée affectée. Les doublons sont idempotents ; une position future ou trop ancienne est refusée, l’heure de réception serveur est conservée. L’interface indique la dernière heure et n’affiche aucune « position en direct » sans donnée récente. La collecte GPS démarre explicitement dans Mi ruta et s’arrête à la déconnexion, au changement de compte ou quand l’écran est fermé.

Ordre : F01 conservé → règles/ressources et planning F02/F03 → GPS F04 → avis F05 → analyse/export F06 → tests base isolée et navigateur → migration → publication compilée et vérification du commit servi.


## Ressources complémentaires · 27 octobre 2026

`tms_pro_settings.dimensions` définit quatre clés/unités communes au plus. `tms_pro_order_rules.loads` et `tms_pro_vehicle_rules.capacities` conservent des valeurs numériques non négatives, au plus trois décimales. Les champs absents des anciennes requêtes sont préservés. Une livraison doit renseigner chaque dimension active, même à zéro ; un véhicule sans capacité explicite vaut zéro. Les helpers privés vérifient le cumul de la tournée dans le planificateur, le déplacement, l’affectation et le contrôle de départ. Le trigger sur `sales_deliveries.departed_at` couvre également le départ individuel historique. Les mutations de configuration, le planning, les déplacements et les départs RPC prennent le même verrou de configuration avant leurs verrous métier.

Les profils conducteur contiennent `start_location`, `end_location`, `end_mode`. Un trigger serveur initialise `tms_routes.route_points` et protège cet instantané des remplacements clients. Les mêmes points servent à la faisabilité, aux kilomètres, aux trajets vérifiés, à la carte et à la navigation. Les identifiants historiques `__depot` restent inchangés : occurrence initiale = départ, occurrence finale = arrivée. Changer de conducteur invalide un horaire si ses points changent. Les anciennes tournées `{}` conservent le dépôt partagé ; aucune reprise de données métier.

`tms_pro_timing` calcule une seule fois attente, pause, service et retour pour la faisabilité et l’ETA enregistrée. Il corrige la réserve doublée d’une pause future qui empêchait à tort les journées courtes. Aucun temps routier externe ni trafic ne sont inventés.
