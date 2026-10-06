# Coco ERP — audit de performance et de sécurité du 6 octobre 2026

## Périmètre et méthode

Référence initiale : `c2127cf55b92e0b5eb888dbc5c078c964b915347` du dépôt `lisciandraj/Pro-manager-Gama`. Analyse du code ERP, du site public Cloudflare Pages, des fonctions Supabase, des migrations, de PostgreSQL et du connecteur SRI Python. Contrôles de production en lecture seule, sauf déploiement des corrections autorisées. Aucune facture réelle, invitation utilisateur ou transmission fiscale n'a été émise pour cet audit.

Les contrôles couvrent les permissions, la RLS, les sessions et la MFA, les injections HTML, les politiques CSP, les dépendances, les limites des requêtes HTTP, les caches, les index, la livraison des fichiers et les tests de régression. Ce rapport ne constitue pas un test d'intrusion exhaustif ni une certification : l'hébergement privé du signataire SRI, les postes utilisateurs, les journaux historiques et la restauration des sauvegardes n'ont pas été accessibles ou exercés.

## Résultats et corrections

| Priorité | Écart observé | Correction | État et preuve |
|---|---|---|---|
| P0 | Ancienne API d'administration : contrôle serveur insuffisant des droits | Vérification de l'utilisateur réel, de son activité, du rôle administrateur, de l'autorisation de module et de la MFA ; validation et retour arrière de la création si refus | Fonction `gama-admin-users` déployée ; tests de refus et d'annulation |
| P0 | Anciennes entrées fiscales encore disponibles | Deux endpoints historiques renvoient 410 et dirigent vers `gama-sri`, sans lire de certificat ni appeler le prestataire | Deux fonctions déployées avec vérification JWT |
| P1 | Interpolation HTML de données métier et gestionnaires inline incompatibles avec une CSP stricte | Échappement des champs et attributs ; photos limitées aux formats raster ; actions déléguées avec liste explicite de callbacks | Sources et fichiers générés corrigés ; tests XSS et commandes UI |
| P1 | Dépendances vulnérables ou chargées depuis un CDN mutable | jsPDF 4.2.1, SheetJS 0.20.3, ZXing local ; manifeste et SRI vérifiés ; dépendances npm/Python corrigées | npm : 1 vulnérabilité haute → 0 ; résolution Python : 31 signalements → 0 vulnérabilité connue |
| P1 | Corps HTTP sans borne uniforme avant parsing/signature | Lecture par flux avec limites de taille, délai, UTF-8 et forme JSON ; redirection amont refusée ; SRI Python borné avant HMAC | Fonctions Supabase et serveur storefront corrigés ; Python corrigé dans le dépôt |
| P1 | Cache client sans séparation robuste des sessions | TTL 30 s, maximum 50 entrées, invalidation au changement d'identité, rejet des réponses de l'ancienne session, éviction des erreurs | Tests de changement d'utilisateur et de réponse différée |
| P1 | Pagination susceptible de tronquer silencieusement les données au plafond serveur | Reprise à partir du nombre réellement reçu ; détection d'une plage ignorée | Tests de pagination et d'import |
| P1 | Contrôles RLS exécutés pour chaque ligne | Sous-requêtes scalaires pour helpers indépendants de la ligne ; fusion des politiques permissives de même rôle et commande | Migration appliquée ; 343 politiques restrictives publiques conservées |
| P1 | Index de clés étrangères manquants et doublons | 225 index de couverture créés, dont 208 publics et 17 privés ; retrait contrôlé de 5 doublons exacts | Conseiller Supabase : 172 alertes FK et 5 doublons → 0 |
| P1 | Vérification MFA/session incomplète dans le helper SQL partagé | Refus des comptes absents/bannis et sessions expirées ou rattachées à un autre utilisateur ; MFA vérifiée si facteur enrôlé | Tests DB isolés ; compatibilité conservée pour les JWT historiques sans session_id |
| P1 | Droits EXECUTE implicites trop larges pour les futurs helpers | Révocation des fonctions internes et des droits par défaut public/anon/authenticated ; grants utiles conservés explicitement | Tests d'accès multi-rôles |
| P1 | Protection CSP ERP trop permissive et dépendances externes | Scripts locaux et hashes du bootstrap de confiance ; aucun script inline arbitraire ni eval ; `object-src 'none'` | Génération et vérification automatiques de chaque entrée HTML |
| P1 | Protection HTTP du site public perfectible | HSTS un an, `object-src 'none'`, `upgrade-insecure-requests` ; maintien de frame DENY et nosniff | Configuration Pages incluse dans la livraison |
| P2 | Détection de vulnérabilités absente des portes de validation | Contrôles npm audit, pip-audit, vendor/SRI et tests de sécurité ajoutés à la CI | Workflow de livraison actualisé |

La migration de production est `20261006214828_performance_security_audit.sql`. Elle n'a modifié aucune ligne métier. Toutes les 202 tables publiques restent sous RLS, les 5 vues auditées utilisent `security_invoker`, les 4 buckets restent privés.

## Mesures de performance

Requête identique exécutée sous le rôle `authenticated`, avec les claims d'un administrateur actif, pour lire 200 produits actifs triés par ID. `EXPLAIN (ANALYZE, BUFFERS)` en transaction annulée. Les données ne sont pas exportées dans le rapport.

| Mesure | Avant | Après |
|---|---:|---:|
| Temps SQL, deux lectures avant / trois lectures après | 904,059 ; 795,249 ms | 66,538 ; 6,452 ; 6,282 ms |
| Accès aux buffers partagés, exemple de plan | environ 16 285 | environ 1 100 |
| Alertes RLS initplan | 26 | 0 |
| Alertes politiques permissives multiples | 110 | 0 |
| Alertes FK sans index | 172 | 0 |
| Alertes index doublons | 5 | 0 |
| JavaScript initial non compressé | 857 785 octets | 865 216 octets |
| Nombre de scripts initiaux | 14 | 14 |
| CSS initial | 230 348 octets | 230 348 octets |

Les lectures après échauffement sont environ 99,2 % plus courtes que les lectures initiales observées. La première lecture après migration est plus lente (66,538 ms). Ces cinq mesures ciblées ne représentent ni un P95 ni une accélération de tout l'ERP. Le poids JavaScript augmente de 0,9 % avec les protections ajoutées et reste sous le budget de 900 000 octets. Les tailles gzip sont des estimations, pas des mesures réseau. LCP, INP et CLS en trafic réel ne sont pas établis par cet audit.

Les 397 alertes informatives d'index inutilisés après migration ne justifient pas leur suppression : les nouveaux index n'ont pas encore d'historique d'utilisation. Observer un cycle métier représentatif avant toute décision.

## Validation

- Validation du dépôt : **294 tests réussis**, génération, types, documentation, migrations et budgets contrôlés.
- Acceptation de sécurité ciblée : **42 tests réussis**, dont equivalence de lecture entre rôles, politiques restrictives, idempotence, comptes bannis, sessions et MFA.
- Connecteur SRI Python : **41 tests réussis** ; aucun envoi fiscal réel.
- Première exécution UI complète : **839 réussites et 31 échecs sur 870 tests**, avec huit workers.
- Comparaison sur le commit initial : **25 de ces échecs reproduits**. Ils concernent surtout des attentes de présentation, traduction ou parcours historiques. Les six autres sont revérifiés séparément avec deux workers avant livraison ; le rapport de livraison donne le résultat définitif.
- Une réussite de tests avec API simulée ne prouve pas le fonctionnement d'un service privé auquel cet audit n'a pas accès.

## Plan d'action restant

Les délais ci-dessous sont des objectifs relatifs à la livraison, pas des rendez-vous déjà programmés.

| Priorité / délai | Action | Responsable | Critère de clôture |
|---|---|---|---|
| P1 — sous 48 h | Enrôler puis exiger la MFA pour les administrateurs ; vérifier un accès de secours avant enforcement | Administrateur Supabase / responsable ERP | Facteurs vérifiés pour les comptes privilégiés, connexion aal2 et essai de récupération |
| P1 — sous 48 h | Réviser les 5 administrateurs actifs parmi 6 comptes Auth | Propriétaire ERP | Chaque privilège justifié ; droits inutiles retirés sans bloquer les opérations |
| P1 — sous 48 h | Activer la protection contre les mots de passe compromis dans Supabase Auth | Administrateur Supabase | Alerte `auth_leaked_password_protection` clôturée ; essai de refus contrôlé |
| P1 — sous 48 h | Imposer la MFA sur le compte Cloudflare après enrôlement des membres | Administrateur Cloudflare | `enforce_twofactor` actif et compte de secours vérifié |
| P1 — sous 7 j | Déployer les exigences et corrections du signataire SRI sur son hébergement privé | Exploitant du signataire SRI | Version effective vérifiée, audit des dépendances sans résultat, test en environnement fiscal de test |
| P1 — sous 7 j | Exercer une restauration de sauvegarde isolée et documenter RPO/RTO | Administrateur base / exploitation | Rapport de restauration et rapprochement des tables métier |
| P2 — sous 7 j | Réconcilier les 25 échecs UI présents avant l'audit et corriger les écarts fonctionnels confirmés | Développement / métier | Tests valides, stabilité à deux workers et conformité métier |
| P2 — sous 14 j | Mesurer LCP, INP, CLS et P95 des parcours principaux avec données anonymisées | Développement / exploitation | Baseline terrain, objectifs et alertes ; pas de PII dans les métriques |
| P2 — sous 14 j | Observer les index pendant un cycle métier, optimiser le chargement du bundle de modules | Développement / administrateur base | Requêtes les plus coûteuses et statistiques d'usage analysées ; budget JS respecté |

La MFA nécessite l'enrôlement des personnes concernées. L'activer de façon globale avant leur enrôlement pourrait couper l'accès à l'ERP. Le déploiement du signataire nécessite l'accès à son hébergement. Ces points ne sont donc pas présentés comme résolus.

## Exploitation et retour arrière

Les sources canoniques sont dans `src/` ; les fichiers racine sont produits par `npm run build`. Le site public est produit par `npm run build:storefront`. Les noms d'API, les RPC et les identifiants de modules sont conservés. Les nouvelles limites HTTP doivent être surveillées sur les erreurs 413/408 pour vérifier qu'un usage normal ne dépasse pas les plafonds.

En cas d'incident UI, revenir à la précédente version de fichiers GitHub Pages ou Cloudflare Pages. Les index ajoutés et la transformation des politiques ont été testés indépendamment ; une annulation DB doit rétablir les définitions exactes de la migration précédente dans une nouvelle migration, après revue, sans supprimer de lignes métier. Ne pas supprimer tous les nouveaux index à l'aveugle. Conserver le refus des endpoints fiscaux historiques et les vérifications d'autorisation.

## Références primaires

- Supabase : https://supabase.com/docs/guides/database/postgres/row-level-security
- Supabase : https://supabase.com/docs/guides/auth/password-security
- jsPDF : https://github.com/parallax/jsPDF/releases
- SheetJS : https://docs.sheetjs.com/docs/getting-started/installation/standalone/
- FastAPI : https://fastapi.tiangolo.com/release-notes/
- Starlette : https://www.starlette.io/release-notes/
- Cloudflare Pages : https://developers.cloudflare.com/pages/how-to/upload-custom-worker/
