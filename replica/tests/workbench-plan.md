# Vérification de la maquette horizontale Coco

Périmètre : tous les modules activés, plus leurs composants partagés. Fixtures locales uniquement, sans écriture métier en production.

| Parcours | Vérification | Suite |
| --- | --- | --- |
| Ouvrir chaque module | Cadre pleine largeur, titre, onglets, absence de débordement à 390/768/1440 px | workbench-layout |
| Menu des applications | Favoris, droits, clavier, fermeture, focus restauré, contenu derrière inerte | workbench-layout, architect-shell, home-order, i18n |
| Devis/commandes | Onglets natifs, recherche serveur, pagination, ouverture et retour, filtres et préférence de vue | workbench-layout, ux-workspace, sales-workspace |
| Tableaux | Quadrillage, tri, colonnes, réordonnancement et cartes mobiles traduites | table-controls, table-views |
| Formulaires | Validation, erreurs, reprise et accès aux boutons sur petits écrans | ux-workspace, responsive-layout |
| Configuration et notifications | Menus, droits, fenêtres, import, sauvegarde et retour | settings-window, notifications-window |
| Contacts | Ouverture, édition, archivage et outils de fusion existants | contacts |
| Langues et tailles | FR/ES/EN, contrôles 320 à 1440 px, Chromium et WebKit | responsive-layout, ux-workspace, workbench-layout |

Le contrôle des écrans de tous les modules ne constitue pas un test intégral de chaque opération métier. Les suites métier existantes, exécutées sur bases isolées, complètent ces contrôles.
