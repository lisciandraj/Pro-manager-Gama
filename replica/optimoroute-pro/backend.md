# Vérification serveur

- Tables additionnelles privées avec RLS, aucun droit direct public/anon/authenticated/service_role.
- Façade authentifiée SECURITY INVOKER ; contrôle de session, MFA, droits TMS et rôle dispatch/chauffeur dans l'implémentation privée.
- Avis public limité au jeton de la livraison complètement réceptionnée, expiration vérifiée et avis unique.
- Aucune nouvelle clé de service ni dépendance fournisseur exposée au navigateur.
- Bornes sur périodes, corps JSON, créneaux, coordonnées, précision, date de mesure, taille et fréquence des positions.
- Mutations de configuration versionnées ; application de planning avec aperçu, verrous et reçu idempotent.
- Historique des nouvelles règles enregistré par les déclencheurs partagés. Les coordonnées brutes ne sont pas recopiées dans l'historique métier.
- Le wrapper d'autorisation des historiques conserve l'implémentation réellement présente lors de la migration, y compris un durcissement comptable absent d'une ancienne copie locale.
- Pas d'activation d'envoi automatique, d'achats, de service routier ni d'application mobile native.
