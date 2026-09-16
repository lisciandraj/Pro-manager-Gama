# Projets — GAMA ERP

Le module utilise l'application HTML/JavaScript existante, Supabase, les profils GAMA, le catalogue de modules, l'Audit Trail et les composants PDF/Excel existants. Il ne conserve aucune donnée métier de projet dans le stockage du navigateur.

## Utilisation

Dans le menu **Projets / Proyectos / Projects**, choisir Portfolio, Mon travail ou Modèles. Un nouveau projet démarre en mode Simple. Les phases, tâches, Kanban, jalons, risques, problèmes, budget, équipe, documents et rapports fonctionnent dans ce mode. Les paramètres permettent d'activer les Work Packages, livrables, changements, RACI, validations de phase, tolérances, Business Case, parties prenantes et le Gantt avec dépendances.

Les modèles intégrés sont disponibles en français, espagnol et anglais. Les administrateurs peuvent ajouter un modèle ou enregistrer la structure d'un projet comme modèle. Les textes saisis par les utilisateurs restent inchangés lors d'un changement de langue.

## Autorisations et intégrité

- Les administrateurs ont accès à tous les projets. Les autres profils internes voient les projets dont ils sont responsables, sponsors ou membres. Les comptes clients et inactifs n'ont pas accès au module.
- Les responsables gèrent le projet et ses affectations. Les membres modifient leurs éléments opérationnels. Les lecteurs peuvent consulter et réaliser une validation qui leur est explicitement attribuée.
- `public.gama_projects_action` est le point d'entrée des opérations. Le serveur vérifie le profil, le module, l'appartenance au projet, les transitions et les versions des objets. Les tables ont des règles RLS et n'autorisent pas les écritures directes du navigateur.
- Les références proviennent de séquences PostgreSQL, sont uniques et ne sont jamais recyclées. Des trous sont normaux après une transaction annulée.
- Les clés de requête rendent les opérations réessayables sans les appliquer deux fois. Les modifications concurrentes produisent une erreur explicite, puis nécessitent un rechargement.
- Les modifications alimentent `gama_audit`, avec états avant/après. L'historique est accessible dans le projet, ses objets et le module Audit existant.
- Une clôture fige le projet et ses coûts. La réouverture nécessite un administrateur et un motif audité.

## Données et intégrations

Les sept tables `pm_projects`, `pm_items`, `pm_members`, `pm_templates`, `pm_comments`, `pm_files` et `pm_links` stockent uniquement les informations propres aux projets. `pm_items` conserve le type métier de chaque objet, sa hiérarchie et son workflow. Les clients, profils, employés, fournisseurs, produits, achats et articles Knowledge restent dans leurs tables existantes.

Une opportunité gagnée, un devis accepté ou une commande confirmée propose la création d'un projet. Une même source déjà liée ouvre son projet existant. La fiche client affiche ses projets et leurs totaux. Les achats et réservations réutilisent les parcours et les fonctions GAMA. Les leçons peuvent devenir des articles Knowledge liés.

Les alertes sont recalculées depuis les données courantes. Elles apparaissent dans le cockpit et le centre d'action, contribuent au compteur de notifications et ouvrent l'objet ou l'onglet concerné. Le centre existant actualise ses données toutes les 60 secondes lorsque l'application est visible. Ce mécanisme ne crée pas d'envoi automatique d'e-mail ou de notification système hors de l'application.

## Calculs financiers

- **Actual** : quantités reçues × coût unitaire, pour les achats liés.
- **Committed** : quantités restant à recevoir × coût unitaire, pour les achats en brouillon, envoyés ou partiellement reçus.
- **Remaining** : budget − actual.
- **Forecast / EAC** : actual + committed + estimation des coûts restants hors engagements.
- En l'absence d'une estimation explicite, le montant restant du budget sert d'hypothèse : le forecast ne descend pas sous le budget initial.
- **ETC** : forecast − actual ; **VAC** : budget − forecast.

Les montants sont hors taxes. Le rapprochement avec les achats utilise leur devise source et le taux saisi lors du rattachement ; il n'utilise aucun taux de change externe implicite. Le portfolio présente les totaux séparément par devise. La devise du projet est verrouillée dès qu'un achat est lié.

Les heures passées sont conservées sur les tâches. La charge prévue est une estimation sur sept jours, répartie selon les dates et la progression ; il ne s'agit pas d'un moteur de paie ou d'un calcul de coût salarial. Le Gantt affiche les dates, les jalons et les dépendances avec zoom ; il ne réordonnance pas automatiquement les tâches.

## Documents et rapports

Les pièces jointes utilisent Supabase Storage privé et des liens temporaires, avec auteur, date et versions immuables. La limite est de 20 Mo par fichier. Les documents HTTPS existants peuvent être liés sans copie. Il n'existait pas de référentiel documentaire transversal réutilisable : le module reprend le même stockage et les mêmes identités que GAMA.

Les rapports lisent les données à jour et utilisent les exports PDF et Excel existants. Ils permettent de sélectionner les sections. Word n'est pas proposé, car l'application ne dispose pas d'un export Word existant.

## Validation et déploiement

Migration : `supabase/migrations/20260916093638_project_management.sql`. Son identifiant correspond à la migration appliquée en production.

```sh
npm ci
node --test tests/project-management-core.test.cjs tests/project-management-db.test.cjs tests/excel-export.test.cjs
npx playwright test tests/project-management.spec.js --workers=1
```

Le test SQL exécute les workflows et les contrôles d'accès dans PostgreSQL/PGlite. `supabase/tests/project-management.sql` peut aussi être exécuté dans une transaction sur Supabase : il crée des identités et objets de test isolés, puis annule les données. Les tests d'interface relient l'interface réelle au même SQL et couvrent le Kanban, les recalculs, les langues, le mobile, les modèles, les rapports et les liens depuis les notifications. Les vérifications des modules existants restent dans les suites Achats, Réceptions, Commandes, Devis, CRM et Opérations.

En environnement réseau restreint, `PM_QA_ASSETS` peut désigner un répertoire `node_modules` contenant les versions déjà utilisées par GAMA de `jspdf@2.5.2` et `xlsx@0.18.5`. Les tests servent alors ces mêmes fichiers CDN depuis le disque, sans modifier le code de production.
