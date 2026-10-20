# Historique commun des modules

Chaque module autorisé dispose du même historique : actions, notes et propositions Agent Coco, du plus récent au plus ancien. Le panneau est à droite sur ordinateur et s’ouvre en tiroir sur téléphone. Les rubriques de Configuration l’affichent dans leur fenêtre. Ventes, Achats et TMS conservent leur suivi de dossier existant et affichent aussi les nouvelles annotations de source rattachées à leur module ou à leur enregistrement.

La feuille de style commune est appliquée à l’ouverture, y compris si la navigation vers TMS l’a déjà préchargée. Une indication `preload` ne remplace pas une feuille `stylesheet`. Les portraits réservent une taille de 30 × 30 px avant le chargement des styles, puis passent à 24 × 24 px sur téléphone. Un chargement CSS échoué peut être retenté à l’ouverture suivante.

Les nouvelles modifications métier sont indexées après leur réussite par les triggers de la base. Les lignes d’une même transaction, du même auteur et de la même action sont regroupées **avant** pagination. La bulle contient les références ; les premières sont visibles et les autres se déplient. Une simple consultation n’ajoute pas d’action. Les anciennes modifications ne sont pas antidatées ni reconstituées à partir d’hypothèses.

L’index ne contient pas de copie complète des enregistrements. Sa lecture utilise les droits du module et les politiques de la ligne métier actuelle, sous l’identité réelle du lecteur. Une modification de classification d’un document s’applique aussi à son historique. Aucun diagnostic, motif médical, salaire, coordonnées bancaires ou fichier binaire n’est copié dans une bulle. Les liens proposés sont des routes internes autorisées.

## Historique central d’Agent Coco

Le panneau du module Agent Coco reprend les actions et notes attribuées explicitement à Agent Coco/ChatGPT ou à une origine `chat`, dans tous les modules et dossiers autorisés. Il lit les événements existants sans les copier ni modifier leurs dates. Les nouvelles actions apparaissent au prochain rafraîchissement. Les décisions humaines de validation/refus ne sont pas réattribuées à l’agent.

Chaque bulle indique son module d’origine et conserve ses références et liens de dossier. Le regroupement reste limité à une transaction et un module ; la pagination chronologique porte sur l’ensemble du flux. Les politiques de ligne des modules et les contrôles existants de chaque dossier restent appliqués. Les conversations récentes de l’assistant restent distinctes de cet historique métier.

Migration : `20261020174233_agent_central_history.sql`.

## Origine ChatGPT, fichier, import ou mail

Les écritures métier dont l’origine enregistrée est `chat` affichent **Agent Coco**, quel que soit l’assistant utilisé (ChatGPT, Claude ou autre agent). Le compte authentifié reste conservé dans `actor_id`. Les créations, modifications (y compris les photos) et suppressions enregistrent l’action, la date, les références et la source dans l’historique du module ; les dossiers incluent aussi ces événements. Les validations humaines des propositions restent attribuées à leur validateur. Les anciens événements sans origine identifiable ne sont pas réattribués par supposition.

La passerelle `coco_agent` marque automatiquement l’exécution après les contrôles d’autorisation et de validation, puis restaure le contexte. Les opérations SQL directes d’un assistant doivent déclarer leur origine dans la même transaction avec `set_config('coco.activity_source_type','chat',true)`, un `coco.activity_source_id` unique et un `coco.activity_source_label` descriptif. Les règles de maintenance dans `AGENTS.md` imposent de vérifier la couverture des tables et l’historique produit. Une connexion privilégiée sans origine déclarée ne permet pas de distinguer automatiquement une personne d’un agent.

Les actions effectuées dans l’ERP sont suivies automatiquement. Pour une action demandée dans ChatGPT, l’assistant utilise l’API métier existante puis rattache l’origine au véritable enregistrement avec `coco_assistant_bridge('record', …)`. Cette commande vérifie l’existence de l’enregistrement ; elle ne crée pas de donnée métier. Elle est idempotente par compte, origine, module et enregistrement.

Un fichier envoyé ici doit être réellement lu et transféré avant d’être annoncé comme archivé. Une capture d’écran, un nom de fichier, un lien temporaire ou une analyse de mail ne constituent pas l’original archivé. À défaut de transfert de l’original, la proposition Documents permet de joindre le fichier dans l’ERP avant validation. Il n’existe pas d’écoute permanente des pièces jointes de toutes les conversations ChatGPT.

Les nouveaux mails utilisent le relais événementiel existant de la boîte Agent Coco. Ils produisent des propositions à examiner, sans création automatique de données métier. Plusieurs propositions distinctes peuvent partager une même origine, par exemple le contact extrait de la signature et le document associé. Un retraitement du même message et de la même action ne crée pas de doublon. Le contrat historique des devis reste inchangé.

| Proposition | Résultat de la validation |
| --- | --- |
| Contact | Contact prérempli corrigible, lié à un client/prospect existant ou à un nouveau prospect ; vérification de l’email déjà connu |
| Demande d’absence | Demande RH en statut `pendiente`, avec employé et dates vérifiés ; décision RH ultérieure |
| Document | Document et première version dans le stockage privé ; original obligatoire et accès choisi |
| Carburant | Plein via le moteur Flotte, avec véhicule, date, litres, montant et kilométrage |
| Écriture comptable | Écriture comptabilisée via le moteur existant, lignes équilibrées, journal et période vérifiés |
| Note | Suivi source dans le module, sans prétendre créer un autre enregistrement |

Les nouvelles propositions se valident par un administrateur autorisé, ou un responsable RH autorisé pour les absences. Les permissions d’action restent exigées ; la comptabilité exige aussi la portée complète et les droits de création/validation. Les propositions Ventes/Achats/TMS gardent leurs droits existants. La vérification est liée au contenu et à l’auteur pendant dix minutes ; une édition ou un changement métier exige une nouvelle vérification. Les décisions sont atomiques et répétables sans création supplémentaire.

## Sources et maintenance

- Interface : `src/features/processes/order-followup.js`, `module-history.js`, `module-review.js` ; styles communs différés.
- Index et droits : migration `20261017141238_universal_module_history.sql`.
- Relais et décisions : migration `20261017141544_module_assistant_proposals.sql`.
- Contrat de relais : [installation du suivi mail](../development/order-mail-setup.md).
- Tests : `tests/module-history-db.test.cjs` et `tests/module-history.spec.js`, avec les régressions du suivi de dossier.

Les correspondances table/module sont explicites dans `private.coco_history_tables`. Un nouveau module ou une nouvelle table métier doit les compléter avec ses règles de lecture. Les tables techniques, secrets et journaux bruts ne sont pas aspirés automatiquement.

## Piste d’audit séparée

Les événements supplémentaires de **Piste d’audit** ne sont plus intégrés aux historiques des modules et dossiers. Le module Piste d’audit et ses journaux restent disponibles. Les actions métier, notes, sources et propositions habituelles sont conservées, ainsi que les contrôles de droits et les optimisations de lecture.

Migration : `20261018181322_remove_audit_from_module_history.sql`. Régression : `tests/audit-module-history-db.test.cjs` et tests existants des historiques et de la piste d’audit.
