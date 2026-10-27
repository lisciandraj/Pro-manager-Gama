# Publication et retour arrière

Les extensions comptables natives utilisent la publication existante de Coco et son projet Supabase. Chaque lot conserve ses tests, migrations exactes, contrôles de soldes et limites dans ce répertoire. Leur publication progressive ne constitue pas une attestation d'équivalence avec l'ensemble du périmètre Odoo 19.0 Enterprise.

Dernière livraison vérifiée : [imports bancaires et différés groupés du 27 octobre 2026](release-20261027.md), commit applicatif `73cb2c2740d564aeb9d4f973134dba2af4bf33bc`. Les preuves HTTP, CI et Supabase sont reliées dans ce compte rendu ; la navigation authentifiée en production reste distinguée des parcours isolés.

1. Intégrer la version actuelle de `main` dans la branche, reconstruire les sorties depuis `src/`, vérifier les tests serveur isolés et PostgreSQL 17, les parcours FR/ES/EN sur trois largeurs, puis les workflows de non-régression. Conserver les protections existantes.
2. Vérifier la sauvegarde logique ciblée et les totaux de `results.md`. Appliquer uniquement les migrations documentées de l'extension, sans import de données de test ni reprise des documents historiques. Pour la configuration, comparer également les comptes, journaux, périodes et transactions à la sauvegarde conservée.
3. Consigner la version réellement attribuée par Supabase, l'empreinte du SQL appliqué et les résultats de [verify-production.sql](verify-production.sql). La façade publique reste invoker ; l'accès direct aux tables privées et au planificateur est refusé aux clients.
4. Pour la configuration, exécuter [verify-configuration-production.sql](verify-configuration-production.sql) et conserver le résultat agrégé : six tables privées sans accès client, capture d'historique et trigger de validation actifs, nouvelles politiques vides, soldes inchangés. Aligner le nom du fichier sur la version attribuée par Supabase, puis archiver l'empreinte du SQL appliqué sans modifier ses octets.
5. Fusionner la PR après réussite des contrôles. `deploy-coco-pages.yml` produit et publie `dist/`. Exécuter `python3 replica/accounting/verify-web.py --commit <commit-publié> --ref <commit-publié>` : le manifeste `coco-build.json` doit annoncer ce commit et les fichiers servis doivent correspondre aux octets de Git. Le contrôle comprend les échéanciers, les différés, les imports, l'historique et les styles comptables lorsque ces fichiers existent dans la révision attendue.
6. Ne pas créer de facture, paiement ou échéancier fictif en production. Les opérations réelles restent soumises aux droits et à la validation humaine dans Coco. La validation connectée du nouvel écran ne doit activer ni séquence ni verrouillage.

Retour arrière de l'interface : rétablir par commit les sources de l'interface précédente, reconstruire et republier avec les mêmes contrôles ; conserver les tables et écritures. Si le planificateur présente un défaut, désactiver uniquement le job `coco-accounting-plans` après lecture de ses dernières exécutions. Conserver les échéanciers utilisés ; corriger les écritures par le parcours d'annulation motivée et une date ouverte. Ne pas supprimer les lignes du livre ou fabriquer une écriture d'équilibrage.

La configuration est inactive après migration : le retour de l'interface peut
conserver son schéma additif sans renuméroter aucune pièce. Après utilisation,
conserver les compteurs, références finales, exceptions et ajustements ; corriger
vers l'avant. Ne pas abaisser un verrouillage définitif ni supprimer un contrôle
pour faciliter le retour arrière. Si un défaut du trigger est confirmé, préparer
et tester une migration corrective avec les mêmes garanties avant application.

L'extension de valorisation périodique du stock est appliquée, avec activation explicite et sans reprise automatique des mouvements historiques ; voir [ses résultats](results-stock19.md). Les coûts observés et comptes requis doivent être configurés et approuvés avant utilisation. Les autres méthodes de comptabilisation du stock Odoo 19, la gestion multi-sociétés et la reprise historique restent des lots distincts, suivis dans [la matrice](features.csv).

## Lot du 27 octobre : relevés au grand livre et journaux

La PR 249 publie `0263cb443cc7917e160e4e1f76e6b04bcf9c75f1`. Les migrations `20261027112820` et `20261027112825`, leurs empreintes et les 23 contrôles historiques sont détaillés dans [results-bank-import.md](results-bank-import.md). La vérification du manifeste et de dix fichiers servis atteste la publication effective ; les contrôles du serveur et ceux du navigateur connecté sont distingués. Aucun compte transitoire ou début de reprise n’est choisi automatiquement. Le retour arrière conserve le schéma et les pièces utilisées, selon [bank-import-ledger.md](bank-import-ledger.md).

Le diagnostic [stock-transition-19.md](stock-transition-19.md) documente les écarts de données et les conditions de transition. L'extension périodique est publiée par la PR 250 ; [sa preuve HTTP](stock19-web-verification.json) conserve le commit et les empreintes réellement servis.

## Lot du 26 octobre : méthodes et rapprochements partiels

Les trois migrations et leurs empreintes réellement appliquées sont consignées dans [results-partial-matching.md](results-partial-matching.md). La reprise isolée peuplée et les 20 empreintes de production vérifient l’absence de modification de l’historique. Les contrôles HTTP anonymes et SQL des privilèges sont archivés. Les nouveaux paramètres restent inactifs et les nouvelles tables vides après installation.

Vérifier après publication `coco-build.json` et les actifs réellement référencés par `architect-assets.js`, en particulier `coco-modules.js`, `gama-payments.js`, `gama-accounting.js`, `coco-accounting-configuration.js` et les catalogues FR/EN/serveur. La session actuelle étant déconnectée, cette vérification de déploiement ne constitue pas une validation connectée des écrans de production.
