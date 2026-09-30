# Revue complémentaire Coco ERP — 30 septembre 2026

Révision analysée : `bbcc400100a74d2bf0533778b44f3682352788eb`, après la réorganisation décrite dans [l’audit initial](2026-09-30.md).
Le dépôt contient 934 fichiers suivis : 122 sources JavaScript, 61 feuilles de style canoniques, 218 migrations SQL actives, quatre entrées Edge Functions, un service SRI Python, 100 suites navigateur et 63 suites Node.
L’inventaire couvre le dépôt ; l’examen statique porte sur les sources frontend, la construction, les contrats et migrations SQL, les fonctions serveur et la documentation courante. Les tests ciblés sont exécutés par GitHub Actions sur la branche de cette livraison. Cette revue ne constitue pas une vérification exhaustive de chaque règle métier ni une mesure de la production.

## Changements livrés

| Sujet | État vérifié au départ | Évolution |
| --- | --- | --- |
| PDF | jsPDF local, 365 730 octets, téléchargé à chaque démarrage | Chargement au premier export, requête partagée, intégrité SHA-384 conservée, reprise après erreur |
| Exports | Constructeurs synchrones utilisés par plusieurs domaines | API existantes conservées ; devis, achats, factures internes, archives, entreprise, projets, preuves de livraison et étiquettes attendent `GamaPdf.ready()` |
| Traductions | Un lot de mutations peut rescanner un parent et ses descendants | Un seul scan par racine ; les descendants déjà couverts sont éliminés |
| Mises à jour | Plusieurs commandes à reproduire et séquence CI dupliquée | `npm run update` reconstruit et valide ; `npm run validate` partage les contrôles locaux et de release |
| Performance | Aucun plafond de taille au démarrage | Budget versionné et vérifié en CI, tailles exactes et estimation gzip reproductibles |

Le point de départ comporte **95 scripts déclarés et 2 308 276 octets de JavaScript**, ainsi que 12 feuilles CSS et 285 783 octets. Ces chiffres sont calculés à partir des URL de `src/app/index.html` et des fichiers de la révision analysée ; ils diffèrent du relevé initial, qui porte sur une autre révision.
Le report du moteur PDF retire 365 730 octets du chargement initial, avant le petit coût du chargeur ajouté. Il ne réduit pas la taille du PDF produit. Au premier export, ce téléchargement reste nécessaire ; les suivants partagent le moteur installé.
Le budget final exige au maximum 2 000 000 octets de JS, 300 000 octets de CSS et 94 scripts déclarés. Les requêtes dynamiques Supabase et ses extensions ne sont pas incluses dans ces totaux.

## Architecture et maintenance

- Les sources sont sous `src/`, et `config/runtime-assets.json` possède les adresses publiques et l’ordre CSS.
- Le build compile les traductions, génère les copies compatibles, le noyau Vite, les versions de contenu, les trois entrées et le service worker, puis prépare `dist/`.
- `vendors` déclare les bibliothèques locales chargées à la demande dont l’URL doit recevoir une version par contenu ; ce tableau ne les ajoute pas aux scripts de démarrage.
- La navigation garde ses identifiants publics, les objets Gama/Architect et les clés stockées. Les permissions et mutations métier restent contrôlées par le serveur.
- Le site GitHub Pages, les migrations, les Edge Functions et le signataire SRI conservent des déploiements distincts.

## Revue par domaine et travaux restants

| Domaine | Contrat actuel | Limite ou suite concrète |
| --- | --- | --- |
| Accès / sessions | Profil serveur, transport Supabase, RLS et commandes autorisées | Le rejet du chargeur SDK Supabase reste mémorisé après un échec ; étudier une reprise de toute la chaîne de démarrage, pas seulement du script |
| Produits / stocks | Stock localisé, réservations, lots, ajustements ; invalidation des caches | Mesurer les listes réelles et conserver les tests de concurrence PostgreSQL |
| Ventes / devis / achats | Documents liés aux processus et références serveur | Les générateurs `build()` restent synchrones ; les nouveaux appels doivent attendre le moteur |
| CRM | Colonnes explicites, comptages head/exact, référentiels communs | `suma()` et `embudo()` font des lectures sans pagination : au-delà de la limite REST, les sommes peuvent être incomplètes ; privilégier un agrégat serveur testé |
| Projets / notifications | Alertes Projets appelées par le badge et la fenêtre de notifications | Extraire les alertes avant de différer le workspace de 70 Ko ; conserver la vérification des changements de session |
| Retours / SAV / documents | Entrées différées et commandes serveur | Revalider les plafonds d’avoirs/remboursements sur les parcours existants |
| Comptabilité / SRI | Gestion comptable distincte de la signature et de l’autorisation fiscale | Les tests simulés ne prouvent pas la disponibilité du signataire privé ni une autorisation réelle |
| TMS / flotte | Chargement différé, preuves, photos et signature | Les exports attendent maintenant le moteur ; les essais physiques caméra/iOS restent nécessaires |
| RH / contacts | Modules communs et restrictions serveur existantes | Continuer les tests de confidentialité et de changement de rôle |
| Recherche / UI / traductions | Catalogue local, annotations opt-in, scans DOM | Le catalogue de 519 Ko reste initial ; mesurer avant de séparer les langues et préserver le changement instantané de langue |
| Construction / CI | Sources et sorties contrôlées ; budgets partagés | Les scripts classiques restent nombreux et des modules IIFE volumineux subsistent ; une conversion doit suivre les dépendances réelles |
| Base | 218 fichiers SQL, 113 noms de fonctions définis au fil des migrations | Ne pas réécrire les migrations historiques ; les alertes de production de l’audit initial n’ont pas été réévaluées ici |

## Validation

La livraison ajoute des tests de partage du téléchargement PDF, d’intégrité, de compatibilité des constructeurs et de reprise après panne réseau ou SDK absent. Les parcours navigateur vérifient l’absence de jsPDF à l’accueil, la production de vrais PDF de devis/achat/preuve et le téléchargement d’une étiquette par le bouton existant.
Les workflows couvrent aussi les exports existants, projets, TMS, ventes, achats, stocks, accès, traduction et responsive.

Pour reproduire :

```sh
npm ci
npm run update
npx playwright install chromium
npm test
node scripts/check-performance.cjs --json
```

Les fixtures SQL utilisent des bases isolées. Aucun changement SQL ou déploiement serveur n’est effectué par cette revue. Les temps sur un téléphone réel, la couverture complète des règles métier et les performances de production restent à mesurer séparément.
