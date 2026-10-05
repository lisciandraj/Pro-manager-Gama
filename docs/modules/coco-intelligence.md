# Agent Coco

État : 5 octobre 2026. Le nom affiché est **Agent Coco**. L’identifiant `assistant-ia`, le point d’entrée `GamaAssistant` et la fonction Edge `gama-assistant-ia` restent compatibles avec la navigation et les droits existants.

## Conversation

Le module comporte deux onglets : **Conversation** et **Rapports d’analyse**. La conversation conserve les messages libres, les réponses avec leurs preuves, les conversations récentes et la connexion OpenAI. Les diagnostics, filtres de période, cartes de recommandations et raccourcis d’analyse autonomes ont été retirés. L’action Edge `diagnostic` est refusée ; l’historique affiché concerne les conversations OpenAI. Les calculateurs partagés avec Stock et le Dashboard restent disponibles dans leurs modules.

L’accès exige un administrateur actif, le module activé, les droits de son profil et la MFA lorsqu’elle est configurée. Le serveur contrôle chaque demande et conserve les historiques par utilisateur. La conversation consulte les données autorisées ; elle ne poste pas de commande, paiement ou écriture comptable. Les clés restent chiffrées côté serveur. Les lectures utiles à la réponse peuvent être transmises au fournisseur OpenAI avec `store: false`.

## Rapports PDF

Le tableau affiche la date, le numéro unique, le titre, la période et le téléchargement PDF. Le tri initial présente les dates les plus récentes ; il peut être inversé. La pagination est de 25 rapports. La liste charge uniquement les métadonnées. Le PDF est chargé à la demande, avec une nouvelle vérification des droits ; son empreinte SHA-256 est vérifiée avant le téléchargement.

Le nouveau type documentaire `agent_report` utilise le préfixe **RCO** et le compteur central de l’ERP, par exemple `RCO-00000001`. Le document téléchargé porte ce numéro dans son nom. Le contenu original du PDF est conservé sans modification. Chaque édition est immuable : une même clé et le même contenu retournent le document existant ; une édition contradictoire est refusée.

Les originaux se trouvent dans `private.agent_report_files`, séparés des métadonnées de `private.agent_reports`. Les tables et l’import interne sont fermés aux visiteurs, comptes clients, utilisateurs non administrateurs et accès direct authentifié. Aucun rapport n’est publié parmi les fichiers du site ou dans Git. Chaque fichier est limité à 5 Mio.

Les deux éditions historiques intégrées sont le diagnostic bilingue du **29 septembre 2026** (12 pages) et le rapport hebdomadaire bilingue du **5 octobre 2026** (32 pages, période du 28 septembre au 4 octobre). Le diagnostic est archivé sous **RCO-00000001** et le rapport hebdomadaire sous **RCO-00000002**. L’automatisation hebdomadaire existante conserve son envoi par mail et archive le même PDF dans Agent Coco. Elle utilise une clé stable `weekly:<début>:<fin>` ; une reprise ne crée pas de deuxième édition. Cet archivage complète la tâche existante ; il ne crée pas une seconde planification.

## API et validation

`gama_agent_reports(p_action, p_data)` expose `list`, `download` et `import`. L’import par l’interface exige le droit de création ; le téléchargement exige le droit d’export. `private.agent_report_import_data(jsonb)` sert uniquement à l’import privilégié des rapports, avec les champs `report_key`, `title`, `report_date`, `period_from`, `period_to`, `languages`, `filename`, `content_base64` et `sha256`. Il ne modifie aucune donnée produit, fournisseur ou client.

La migration `20261005165044_agent_coco_report_archive.sql` installe le préfixe, le compteur, les tables privées et les RPC. Les tests `agent-coco-reports-db.test.cjs`, `assistant-server.test.mjs` et `assistant-ia.spec.js` vérifient références, déduplication, refus des conflits, confidentialité, tri, pagination, conversation et changement de session.
