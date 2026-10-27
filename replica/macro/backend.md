# Backend

- [x] Identités, rôles et MFA Coco existants réutilisés.
- [x] Tables privées avec RLS, lectures bornées et écritures par fonctions contrôlées.
- [x] Second membre, autre administrateur, client, compte inactif et retrait d'accès testés.
- [x] Sources résolues par fonction invocateur ; aucun droit hérité d'un simple lien.
- [x] Clés idempotentes et tâche + lien atomiques, sans second moteur métier.
- [x] Historique sans copie du corps des messages ; auteur conservé.
- [x] Aucun secret, clé fournisseur, nouveau service, paiement ou envoi de mail ajouté.

La mise à jour utilise une migration additive. Les prototypes et essais sont
isolés des données réelles. La publication du site est distincte de l'installation
de cette migration ; les deux doivent être vérifiées avant de déclarer le module
en production.
