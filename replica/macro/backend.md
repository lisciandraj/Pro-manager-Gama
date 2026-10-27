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

## Documents collaboratifs

Migration installée sous `20261027225549` ; les octets archivés correspondent au
registre réel. Quatre tables privées avec RLS, aucune exécution anonyme, aucun
accès du navigateur au point de préparation des reçus. L’OID du résolveur et
l’empreinte de la politique d’historique sont inchangés après installation.

La fonction `coco-workhub-documents` v1 et Agent Coco v8 sont actifs avec
vérification JWT. Les cinq fichiers documentaires et les six fichiers Agent
relus dans le service correspondent exactement aux sources locales testées.
Les essais utilisent uniquement des bases isolées ; aucun document fictif créé
en production. Le site est publié à la révision
`559886e049936addd7913375047325d289b46901`, avec ses contrôles existants
réussis et ses fichiers publics comparés aux sources construites.
