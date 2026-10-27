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


## Extension des ressources · 27 octobre 2026

- Migration additive : `20261027204533_tms_resource_loads_and_endpoints.sql`. Pas de nouvelle table ni de nouvelle façade publique. Fonctions remplacées sur leur identité existante ; aucune nouvelle enveloppe d’autorisation d’historique.
- Validation : quatre dimensions maximum, clés uniques, unités stables dès utilisation, 0–1 000 000 et trois décimales, noms et coordonnées bornés. Champs omis préservés pour les anciens clients.
- Cumul des charges au planning, déplacement manuel, affectation directe, état de départ et trigger de départ de l’expédition. La collecte GPS et la projection publique client ne changent pas.
- Instantané serveur des lieux ; l’application et le conducteur autorisé peuvent les lire sous les politiques existantes des tournées. Pas de coordonnées ni de charge dans le journal commun d’activité.
- Les essais passent exclusivement dans les bases isolées de restauration. Aucune livraison ou position de test en production.
