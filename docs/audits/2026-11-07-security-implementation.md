# Mise en œuvre de la sécurité — 7 novembre 2026

Cette livraison répond aux quinze priorités de la revue du site public et de Coco ERP. Elle distingue les corrections vérifiées sur des données factices de l’activation des services réels. Aucun enrôlement MFA personnel, sauvegarde distante ou exercice de reprise réel n’est simulé comme accompli.

## Couverture des quinze actions

| N° | Mise en œuvre | Activation ou preuve d’exploitation |
| --- | --- | --- |
| 1 | Export technique chiffré, inventaire de coffre séparé, marqueur atomique, surveillance de fraîcheur, modèles systemd et restauration isolée. | Hôte privé, `pg_dump 17`, `age`, destination indépendante, identifiants et exercice de restauration encore nécessaires. Voir [reprise](../operations/recovery.md). |
| 2 | Politique serveur de MFA obligatoire, état personnel disponible avant lecture métier, enrôlement guidé, activation conditionnée aux facteurs vérifiés et à la récupération, preuve fraîche liée aux actions sensibles. | Le relevé du 7 novembre compte six administrateurs actifs, aucun facteur vérifié et aucune activation persistante. Chaque personne doit enrôler son propre facteur avant activation globale. Ne pas couper les accès avant la publication du parcours. |
| 3 | Export applicatif limité à des ressources et colonnes explicites, contrôlé côté serveur, exclusions déclarées, données sensibles non exportées par copie indirecte d’audit ; enveloppe chiffrée et vérification des anciens formats. | L’export métier ne remplace pas la sauvegarde technique. Le contrôle d’action est une cohérence de permission, pas une séparation de fonctions face à un administrateur qui gère déjà les droits. |
| 4 | Validation de release et recherche de secrets sur l’historique complet exigées dans le graphe de publication, même révision et artefact vérifiés. | La lecture des règles de branche avec la connexion GitHub actuelle retourne HTTP 403. Le propriétaire disposant de l’administration doit appliquer et constater les règles déclarées. |
| 5 | Favoris B2B soumis au même contrôle de catalogue que le catalogue et le panier, y compris après changement d’autorisation ; suppression toujours possible. | Tests SQL avec clients et produits factices ; aucun accès au tarif d’une autre entreprise n’est revendiqué. |
| 6 | Manifestes de provenance des actifs, empreintes des migrations/fonctions/services et outil de comparaison aux observations réelles. | Une compilation ne prouve pas un déploiement. Vérifier ERP, Cloudflare, Edge, SQL et hôte SRI séparément ; préserver toute modification concurrente. |
| 7 | Garde Projets réutilisant le contrôle commun de module tout en conservant membre, responsable, sponsor et portée des fichiers. | Tests de retrait/réactivation du profil sur RPC, SELECT et politique de fichiers. |
| 8 | Sérialiseur CSV commun, texte neutralisé et nombres typés conservés, appliqué aux exports généraux et historiques. | Tests de cellule bénigne, espaces/tabulations, séparateurs et nombres négatifs ; [contrat CSV](../development/browser-file-security.md). |
| 9 | Admission atomique avant allocation Workhub, plafonds de reçus, compteur de commits sérialisé, reprises sans nouvelle allocation, purge indépendante des reçus techniques expirés. | Tests du refus avant stockage, croissance bornée, conflit, reprise et purge ; aucun document métier ni historique de commit supprimé. |
| 10 | Justificatifs validés au point de stockage commun et au navigateur ; `document.write` remplacé par DOM/Blob ; en-têtes HTTP restrictifs générés pour un hébergement compatible. | GitHub Pages n’interprète pas `_headers`. Le raccordement d’une origine ERP maîtrisée reste nécessaire pour activer les en-têtes HTTP ; ne pas prétendre que les en-têtes du site public protègent l’ERP. |
| 11 | Chiffrement IA versionné avec clé dédiée, lecture historique et rotation explicite ; consultation SRI par capacité machine limitée. | Provisionner les clés dans le gestionnaire de secrets, rechiffrer puis retirer les anciennes clés. L’hôte SRI doit être raccordé avant retrait effectif de sa clé globale. |
| 12 | Outil de planification/application ciblée de la politique Auth : longueur serveur, mots de passe compromis, durée JWT, rotation et facteurs TOTP, puis relecture de contrôle. | Le jeton de gestion Supabase n’est pas présent. La protection contre les mots de passe compromis est désactivée dans le relevé réel. Les redirections et limites d’essais doivent être constatées sans remplacement aveugle. |
| 13 | Réservation globale avant chaque appel IA/OCR, concurrence et plafonds quotidiens, registre de modèles, métriques expurgées et contexte limité à la demande. | Le modèle réel observé est `gpt-4.1-mini`. Le plafond financier du compte fournisseur reste nécessaire, notamment pour les médias dont le coût exact n’est connu qu’après traitement. |
| 14 | Actions épinglées par SHA vérifié, images par digest, dépendances Python transitives avec empreintes, contexte Docker limité et mises à jour déclarées. | L’analyse complète de l’historique conserve des exceptions étroites documentées pour les constantes publiques et fixtures ; les canaris de clés privées restent détectés et expurgés. |
| 15 | Outils de fraîcheur, intégrité, signaux de sécurité, rétention contrôlée, exercice d’incident à blanc et procédures de révocation. | Raccorder collecteur, destinataire, ordonnanceur et coffre. Les durées juridiques et gels légaux doivent être approuvés avant purge des données métier. Voir [surveillance](../operations/security-monitoring.md). |

## Ordre de livraison

1. Tester la reconstruction complète avec Node.js 22, les migrations et les scénarios de refus ; reconstruire les actifs canoniques. Conserver la livraison concurrente des parcours simplifiés.
2. Comparer les définitions SQL effectives et le registre de migrations. Appliquer uniquement les nouvelles migrations revues, avec leurs empreintes. Ne pas rejouer l’historique ni réparer ses horodatages.
3. Publier l’interface après les contrôles de release. Les Pages Functions, Edge Functions et services Python restent des livraisons distinctes ; les migrations de budget précèdent les fonctions IA/OCR qui les utilisent.
4. Préparer un compte d’administration de secours et les facteurs personnels ; activer ensuite la politique obligatoire depuis le parcours protégé. Le statut en attente ne signifie pas que les comptes sont déjà protégés.
5. Fournir les liaisons opérationnelles manquantes, exécuter le contrôle à blanc puis une sauvegarde/restauration isolée. Ne pas annoncer de RPO/RTO avant cet exercice.

## Commandes de vérification

Les commandes locales emploient des fixtures et des services simulés, pas des données de production.

```sh
npm run build
npm run build:storefront
npm run validate
node --test tests/auth-security-policy.test.mjs tests/release-security.test.cjs
node tests/security-access-hardening-db.test.cjs
node tests/workhub-quota-hardening-db.test.cjs
node tests/receipt-content-hardening-db.test.cjs
node tests/ai-provider-budget-db.test.cjs
python3 -m unittest discover -s tests -p 'test_coco_operations.py' -v
```

Les tests du parcours d’identité, des exports chiffrés et du navigateur complètent ces contrôles. Le compte rendu de livraison doit donner les résultats réellement observés, les identifiants de migration et les versions publiées ; les commandes ci-dessus seules ne sont pas une preuve de réussite.

Le plan Auth peut être consulté sans mutation par `node scripts/auth-security-policy.mjs` avec `SUPABASE_ACCESS_TOKEN` fourni par le gestionnaire de secrets. `--apply` effectue uniquement un PATCH des champs contrôlés puis les relit ; les secrets SMTP, clés et paramètres non concernés ne sont jamais imprimés. L’outil refuse un autre projet. Voir le [contrat officiel Auth](https://supabase.com/docs/reference/api/v1-update-auth-service-config).

## Retour arrière

Republier un artefact identifié par son SHA pour revenir sur l’interface. Préférer une migration corrective ciblée pour les gardes SQL. Ne pas supprimer les clés hors ligne, reçus de commande ou événements métier pour revenir sur du code. Conserver le refus des produits B2B interdits et de la révocation Projets ; désactiver une capacité machine ou les nouvelles dépenses IA en cas d’incident. La politique MFA conserve les activations personnelles déjà effectuées ; toute récupération doit rester tracée et administrée.

Références complémentaires : [livraison](../development/security-release.md), [IA/SRI](../development/ai-security-controls.md), [reprise](../operations/recovery.md), [surveillance](../operations/security-monitoring.md).
