# Revue de maintenance Coco ERP — 30 septembre 2026

Révisions examinées : `bbcc400100a74d2bf0533778b44f3682352788eb`, puis `9d8889fb9ff9ed77bb71f0e5b1f88611c0779239` intégrée pendant cette revue. Cette livraison conserve les extractions PDF/Projets, le correctif Vite 6.4.3 et les protections de session de cette dernière révision.
Voir [l’audit des domaines](2026-09-30.md) et [l’audit du chargement](2026-09-30-runtime.md).

L’inventaire initial couvre 934 fichiers : 122 sources JavaScript, 61 feuilles de style canoniques, 218 migrations SQL, quatre entrées Edge Functions et le service SRI Python. L’examen statique couvre les sources frontend, les migrations, les fonctions serveur, les outils et la documentation ; les 100 suites navigateur ont été parcourues pour identifier les contrats PDF. Cette revue n’atteste pas chaque règle métier ou la vitesse en production.

## État actuel et simplifications ajoutées

| Sujet | État actuel |
| --- | --- |
| Chargement | PDF et écrans Projets à la demande ; intégration Projets légère pour les alertes et liens |
| Bibliothèques | Téléchargements partagés dans `ArcLoadScript`, intégrité SRI et vérification de présence du SDK ; reprise après erreur réseau ou SDK absent |
| Traductions | Scans DOM regroupés ; un descendant est couvert par son parent dans le même lot |
| Mise à jour | `npm run update` reconstruit et lance `npm run validate` ; la release partage ces contrôles |
| Budgets | Plafonds JS, CSS et nombre de scripts dans `config/performance-budget.json`, contrôlés par `check:startup` ; scripts dupliqués rejetés |
| Versions | `vendors` du manifeste produit une URL à hash pour jsPDF différé |
| Contrats | Sources canoniques sous `src/` ; API, routes, noms RPC et clés de stockage compatibles |

La révision de départ charge 95 scripts et 2 308 276 octets de JS. L’extraction PDF/Projets déjà intégrée réduit ce total à 93 scripts et 1 877 403 octets, soit 18,7 % de moins. Après cette livraison, le total est **1 877 820 octets et 93 scripts** (−430 456 octets, soit −18,6 % face à la révision de départ). Le relevé final se reproduit avec `node scripts/check-startup.cjs --json`. Les 12 feuilles CSS représentent 285 783 octets. Les budgets restent 1 900 000 octets JS, 300 000 octets CSS et 93 scripts.

Ces tailles excluent les requêtes dynamiques, images et données ; gzip est estimé fichier par fichier. Elles ne représentent pas une baisse équivalente du temps d’ouverture. Le premier export télécharge encore le moteur PDF ; les suivants réutilisent le moteur installé.

## Points restant à traiter par domaine

| Domaine | Constat et suite |
| --- | --- |
| Accès | La base et les fonctions serveur restent l’autorité. Le rejet du chargeur SDK Supabase demeure mémorisé après échec : étudier la reprise de toute la chaîne de démarrage |
| Produits / stocks | Stock localisé, réservations, lots et invalidations présents ; mesurer les volumes et conserver les tests de concurrence PostgreSQL |
| Ventes / achats / documents | Constructeurs PDF synchrones ; attendre `GamaPdf.ready()` dans tout nouvel appel et conserver les contrôles du parcours |
| CRM | `suma()` et `embudo()` lisent sans pagination : au-delà de la limite REST, les sommes peuvent être incomplètes. Préparer des agrégats serveur avec tests sur gros volumes |
| Projets / notifications | Alertes partagées, chargement différé et invalidation de session présents ; revalider les réponses hors ordre et les liens croisés à chaque extraction |
| Retours / SAV | Chargement différé et commandes serveur ; maintenir les tests de plafonds d’avoirs/remboursements |
| Comptabilité / SRI | Gestion comptable distincte du signataire privé ; les tests simulés ne prouvent pas une signature ou autorisation réelle |
| TMS / flotte | Exports, preuves, photos et signature présents ; tester caméra, scan et téléchargements sur iPhone physique |
| RH / contacts | Contrats serveur et confidentialité à préserver pendant les changements de rôle |
| Recherche / UI | Catalogue de traduction de 519 Ko encore initial ; mesurer avant de séparer les langues |
| CI / architecture | Modules IIFE volumineux et nombreux scripts classiques ; poursuivre les extractions à partir des dépendances observées |
| Base | 218 fichiers SQL, 113 noms de fonctions définis au fil des migrations ; conserver l’historique et la procédure de restauration |

Les alertes Supabase décrites dans l’audit du chargement n’ont pas été réévaluées pendant cette revue. Aucun changement SQL, fonction serveur, stock ou document fiscal n’est effectué.

## Validation reproductible

```sh
npm ci
npm run update
npx playwright install chromium
npm test
node scripts/check-startup.cjs --json
```

Les tests ajoutés vérifient la reprise lorsque le SDK PDF manque et l’étiquette par son bouton existant. Les tests de PDF réels et de marque entreprise utilisent la copie locale ; les suites existantes vérifient chargement, accès, session, Projets, TMS, stocks, ventes, achats, traductions et responsive. Les fixtures SQL utilisent des bases isolées.
Les résultats de la CI sur la dernière révision de la PR constituent la preuve d’exécution ; un résultat d’une ancienne révision ne garantit pas la version finale.
