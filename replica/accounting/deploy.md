# Publication et retour arrière

La PR 243 contient l'extension additive et la matrice des écarts. Elle ne constitue pas la livraison de l'ensemble du périmètre Odoo.

1. Intégrer la version actuelle de `main` dans la branche, reconstruire les sorties depuis `src/`, vérifier les tests serveur isolés et PostgreSQL 17, les parcours FR/ES/EN sur trois largeurs, puis les workflows de non-régression. Conserver les protections existantes.
2. Vérifier la sauvegarde logique ciblée et les totaux de `results.md`. Appliquer uniquement la migration native des échéanciers, sans import de données de test ni reprise des documents historiques.
3. Consigner la version réellement attribuée par Supabase, l'empreinte du SQL appliqué et les résultats de [verify-production.sql](verify-production.sql). La façade publique reste invoker ; l'accès direct aux tables privées et au planificateur est refusé aux clients.
4. Fusionner la PR après réussite des contrôles. `deploy-coco-pages.yml` produit et publie `dist/`. Lire le manifeste `coco-build.json` du site et vérifier son commit exact et la présence de l'actif `coco-accounting-plans.js`.
5. Ne pas créer de facture, paiement ou échéancier fictif en production. Les opérations réelles restent soumises aux droits et à la validation humaine dans Coco.

Retour arrière de l'interface : rétablir par commit les sources de l'interface précédente, reconstruire et republier avec les mêmes contrôles ; conserver les tables et écritures. Si le planificateur présente un défaut, désactiver uniquement le job `coco-accounting-plans` après lecture de ses dernières exécutions. Conserver les échéanciers utilisés ; corriger les écritures par le parcours d'annulation motivée et une date ouverte. Ne pas supprimer les lignes du livre ou fabriquer une écriture d'équilibrage.

Les futures migrations de stock Odoo 19, multi-sociétés et reprise historique nécessitent une préparation distincte des données et une restauration intégrale attestée. Aucun de ces changements structurels n'est appliqué par cette extension.
