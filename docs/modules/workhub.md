# Espace de travail

La tuile **Espace de travail / Espacio de trabajo / Workspace** rassemble les
discussions et les éléments métier accessibles au collaborateur. Elle s'inspire
des parcours publics de Macro et conserve les composants, les données et les
contrôles de Coco. Sources et périmètre : [reconnaissance](../../replica/macro/recon.md).

## Utilisation

La réception présente les messages des autres membres, les tâches Projets
attribuées à l'utilisateur, ses activités CRM et, pour les administrateurs
autorisés, les propositions en attente du relais mail et d'Agent Coco. Les
filtres Tout, Archivés et Reportés portent sur le classement personnel.
**Archiver une notification ne termine pas une tâche et n'approuve rien.**
Une tâche modifiée après son classement redevient visible. Le report dure
24 heures et ne modifie pas son échéance.

Créer un canal, sélectionner des collègues déjà présents dans Coco et écrire un
message. Les réponses restent sous leur message d'origine. Un message peut
devenir une tâche d'un projet existant : responsable, échéance et priorité sont
enregistrés par `gama_projects_action`, avec un lien vers la discussion d'origine.
Un projet doit exister avant cette création.

**Lier une référence** recherche les tâches, articles Knowledge, documents,
clients et opportunités autorisés. L'aperçu montre les discussions liées dans
les deux sens et permet d'ouvrir le module d'origine. La recherche de l'espace
couvre ces mêmes sources et les messages ; le bouton de recherche ERP conserve
l'accès aux autres dossiers, produits et documents commerciaux de Coco.

Les vues Tâches, Documents et Clients/CRM réutilisent les sources métier. Les
articles et documents continuent d'être créés et édités dans leurs modules.
Le panneau **Contexte de l'équipe** rassemble jusqu'à 30 messages récents du
canal. **Préparer une question pour Agent Coco** ouvre un brouillon borné à la
limite de l'agent, à relire et envoyer volontairement. Il n'exécute aucune action. Agent Coco dispose aussi d'un outil de lecture du
travail partagé : il recherche les discussions, consulte les canaux auxquels
l'administrateur appartient et cite ces lectures comme preuves actuelles.
Cet outil utilise le jeton de l'utilisateur, jamais la clé de service.

## Accès et données

- Profils internes administrateur, commercial et entrepôt, actifs et autorisés
  pour `workhub`. Clients et comptes désactivés sont refusés côté serveur.
- Seuls les membres lisent un canal, y compris pour un autre administrateur.
  Le propriétaire gère ses membres. Le retrait prend effet à la prochaine lecture.
- Un lien n'accorde pas de droit sur une source. Résolution et recherche utilisent
  une façade `SECURITY INVOKER` et les RLS des modules d'origine à chaque lecture.
- Les nouvelles tables privées ont RLS et aucun droit d'écriture directe pour
  le navigateur. Les écritures passent par une fonction privée contrôlée et un
  reçu lié à l'acteur, à l'action et au contenu ; une nouvelle tentative identique
  ne crée pas de second message ou tâche.
- L'historique Coco conserve les auteurs et références des mutations, sans
  recopier le texte du chat. Il est soumis à l'appartenance actuelle au canal.
- Les brouillons de chat restent en mémoire de l'onglet, sont préservés lors
  d'un échec et effacés à la déconnexion. Aucun stockage métier local permanent.
- L'espace charge à l'ouverture. Actualiser relit les données ; le canal ouvert se synchronise aussi toutes les
  20 secondes lorsque l'onglet est visible, sans effacer le brouillon. Cette
  version ne propose pas de diffusion WebSocket ni de synchronisation hors ligne.

## Périmètre livré et limites

Le noyau commun comprend réception, canaux privés, fils, tâches natives, liens
retour, recherche, contexte Agent Coco et classement personnel en FR/ES/EN sur
ordinateur et téléphone. Les mails visibles sont des propositions déjà reçues
par le relais Coco ; cette vue ne remplace pas une boîte Gmail complète.

Les appels/transcriptions, la visioconférence, un calendrier connecté, les liens
de réservation, les éditeurs CRDT, le tableur collaboratif et les agents de code
ne font pas partie de cette tranche. Aucun abonnement ni nouveau fournisseur
n'est activé. Le [suivi de parité](../../replica/macro/features.csv) les conserve
explicitement comme non réalisés.

## Vérification

`node --test tests/workhub-db.test.cjs` reconstruit une base isolée et teste les
RLS, les canaux, les nouvelles tentatives, les tâches natives, les références,
le classement, les retraits de droits et l'historique.
`npx playwright test tests/workhub.spec.js --workers=1` relie la vraie interface
à ce même SQL isolé pour les parcours ordinateur/téléphone, erreurs, langues,
clavier, absence de HTML interprété et analyse axe. Aucun jeu d'essai n'est
écrit dans les données de production.
