# Publication et retour arrière

La PR 243 contient les échéanciers natifs ; la PR 244 prolonge la configuration et l'import des relevés. Ces extensions additives ne constituent pas la livraison de l'ensemble du périmètre Odoo.

1. Intégrer la version actuelle de `main` dans la branche, reconstruire les sorties depuis `src/`, vérifier les tests serveur isolés et PostgreSQL 17, les parcours FR/ES/EN sur trois largeurs, puis les workflows de non-régression. Conserver les protections existantes.
2. Vérifier la sauvegarde logique ciblée et les totaux de `results.md`. Appliquer uniquement les migrations documentées de l'extension, sans import de données de test ni reprise des documents historiques. Pour la configuration, comparer également les comptes, journaux, périodes et transactions à la sauvegarde conservée.
3. Consigner la version réellement attribuée par Supabase, l'empreinte du SQL appliqué et les résultats de [verify-production.sql](verify-production.sql). La façade publique reste invoker ; l'accès direct aux tables privées et au planificateur est refusé aux clients.
4. Pour la configuration, exécuter [verify-configuration-production.sql](verify-configuration-production.sql) et conserver le résultat agrégé : six tables privées sans accès client, capture d'historique et trigger de validation actifs, nouvelles politiques vides, soldes inchangés. Aligner le nom du fichier sur la version attribuée par Supabase, puis archiver l'empreinte du SQL appliqué sans modifier ses octets.
5. Fusionner la PR après réussite des contrôles. `deploy-coco-pages.yml` produit et publie `dist/`. Lire le manifeste `coco-build.json` du site et vérifier son commit exact et les actifs `coco-accounting-plans.js` et `coco-accounting-configuration.js`.
6. Ne pas créer de facture, paiement ou échéancier fictif en production. Les opérations réelles restent soumises aux droits et à la validation humaine dans Coco. La validation connectée du nouvel écran ne doit activer ni séquence ni verrouillage.

Retour arrière de l'interface : rétablir par commit les sources de l'interface précédente, reconstruire et republier avec les mêmes contrôles ; conserver les tables et écritures. Si le planificateur présente un défaut, désactiver uniquement le job `coco-accounting-plans` après lecture de ses dernières exécutions. Conserver les échéanciers utilisés ; corriger les écritures par le parcours d'annulation motivée et une date ouverte. Ne pas supprimer les lignes du livre ou fabriquer une écriture d'équilibrage.

La configuration est inactive après migration : le retour de l'interface peut
conserver son schéma additif sans renuméroter aucune pièce. Après utilisation,
conserver les compteurs, références finales, exceptions et ajustements ; corriger
vers l'avant. Ne pas abaisser un verrouillage définitif ni supprimer un contrôle
pour faciliter le retour arrière. Si un défaut du trigger est confirmé, préparer
et tester une migration corrective avec les mêmes garanties avant application.

Les futures migrations de stock Odoo 19, multi-sociétés et reprise historique nécessitent une préparation distincte des données et une restauration intégrale attestée. Aucun de ces changements structurels n'est appliqué par cette extension.
