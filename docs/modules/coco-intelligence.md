# Agent Coco

État : 5 octobre 2026. Le nom affiché est **Agent Coco**. L’identifiant `assistant-ia`, le point d’entrée `GamaAssistant` et la fonction Edge `gama-assistant-ia` restent compatibles avec la navigation et les droits existants.

## Conversation

Depuis le 18 octobre 2026, les nouvelles réponses d’Agent Coco sont en espagnol (Équateur), quelle que soit la langue de l’interface ou de la question. Cette règle couvre les analyses, plans d’action, questions de clarification et messages de préparation du stock. Les références, noms et justifications métier citées restent fidèles aux sources. Les conversations déjà enregistrées sont conservées.

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

Les nouvelles éditions du rapport automatique et leurs messages d’accompagnement sont également en espagnol, avec `languages: ["es"]` à l’archivage. Les éditions historiques restent immuables. Le relais mail rédige les nouvelles synthèses, notes, descriptions proposées et notifications d’Agent Coco en espagnol ; les en-têtes et références sources sont conservés.

## File d’actions à valider

L’onglet **À valider** d’Agent Coco centralise les propositions structurées des modules. Il fonctionne même sans connexion au modèle IA. Les administrateurs voient uniquement les propositions des modules qu’ils peuvent actuellement réviser. Les états **À valider**, **Exécutées** et **Refusées** sont paginés par 25.

Sélectionner des propositions puis **Vérifier la sélection** produit une revue serveur valable dix minutes. **Valider et exécuter** applique seulement les lignes revues avec succès. Chaque ligne garde son résultat ; un échec n’annule pas les autres lignes. Une nouvelle tentative ne duplique pas une action déjà exécutée. Les propositions incomplètes se corrigent depuis leur historique de module. **Refuser la sélection** demande une confirmation et conserve la trace des propositions.

Dans **Comptabilité → Banque et caisse → Rapprochement**, choisir une facture puis **Envoyer à Agent Coco** crée uniquement une proposition. La revue affiche le compte, la référence bancaire, le montant et les soldes avant/après. La validation enregistre l’encaissement, l’affectation à la facture et le rapprochement dans une transaction, via le traitement bancaire existant. Le statut payé dépend du solde réel ; un paiement partiel ne solde pas artificiellement la facture. Les droits, la période et les données sont contrôlés de nouveau avant exécution.

Le pont de confiance `coco_assistant_bridge('propose', …)` accepte aussi l’action typée `bank_settlement` du module `accounting`, avec seulement `bank_id` et `invoice_id` dans le payload. Il enregistre une proposition, jamais un paiement. La RPC `coco_action_queue` garde la lecture en mode invoker/RLS ; la revue et la décision exigent une session administrateur ERP, pas un jeton OAuth d’agent. Les décisions conservent `decided_by` et l’historique attribue les écritures à Agent Coco.

Les mouvements de stock gardent leur circuit séparé d’approbation MFA, accessible par **Approbations de stock avec MFA** ; ils ne sont pas exécutés par le lot de propositions métier.
