# Suivi des commandes et messagerie

Les fiches Commandes clients et Commandes fournisseurs présentent à gauche le statut et une chronologie partagée. Les écrans conservent les couleurs Coco, une surface de travail blanche, les onglets et les tableaux existants. Le volet est repliable sur téléphone. Les actions opérationnelles, les documents et les activités commerciales restent disponibles.

Le journal regroupe les événements métier existants, les modifications futures de lignes ou d’en-têtes, les notes internes et les échanges mail. Chaque entrée indique l’auteur et la date fournis par le serveur. Une action historique sans auteur reste explicitement signalée ; aucun auteur n’est inventé. Les filtres Tout, Actions, Mails et Notes et le chargement des entrées précédentes permettent de parcourir le dossier.

Les notes suivent les droits de modification du module. Les mails sont réservés aux profils commerciaux et administrateurs autorisés sur le module. Un magasinier ne voit ni les corps des mails ni les étapes financières auxquelles il n’a pas accès. Le lien avec une commande et les droits sont contrôlés côté serveur à chaque lecture et écriture.

## Connexion et utilisation

Un administrateur configure d’abord les applications OAuth suivant le [guide de configuration](../development/order-mail-setup.md). Chaque utilisateur ouvre ensuite **Ma messagerie / Connecter ma messagerie** dans une commande et autorise Gmail ou Outlook / Microsoft 365. La boîte connectée doit correspondre à l’adresse de son compte ERP. Une connexion ChatGPT à Gmail est indépendante de cette connexion applicative.

**Envoyer un mail** ouvre le destinataire, l’objet, le texte et les pièces jointes avant tout envoi. L’expéditeur est imposé par la boîte vérifiée. Le message est partagé avec les collaborateurs autorisés sur la commande. Les pièces jointes sortantes sont limitées à cinq fichiers et 5 Mo au total ; avec Outlook, chaque fichier doit faire moins de 3 Mo. **Répondre** garde le fil du fournisseur de messagerie ; ce bouton est disponible pour le propriétaire de la boîte qui a associé le fil.

Le serveur importe uniquement les fils déjà associés à la commande, pas l’ensemble de la boîte. Les réponses sont recherchées à l’ouverture, via **Actualiser**, puis toutes les 60 secondes tant que la fiche est visible et qu’aucun texte n’est en cours d’édition. Il n’y a pas de service de synchronisation en arrière-plan lorsque l’ERP est fermé. Les messages importés sont dédupliqués par boîte, fournisseur et identifiant du message. Le texte est affiché sans HTML actif ni pixels de suivi. Les noms des pièces jointes reçues apparaissent ; leur téléchargement reste dans la messagerie d’origine.

Les statuts sont distincts : **Envoyé**, **Accepté par le service mail** (réponse Microsoft 202), **Reçu**, **Échec** et **Envoi non confirmé**. Ils ne prouvent ni la livraison ni la lecture. Une erreur réseau ambiguë ne déclenche jamais un second envoi automatique. Pour Gmail, une actualisation recherche après 90 secondes l’identifiant MIME exact dans les messages envoyés afin de rétablir son statut et son fil si l’envoi est retrouvé ; vérifier le dossier Envoyés avant de rédiger un nouveau message. La déconnexion supprime l’accès à la boîte et ses demandes OAuth en attente, tout en conservant l’historique métier.

Le bouton fournisseur **Envoyer la commande par e-mail** joint le PDF et ne fait passer le brouillon à l’état Commande passée qu’après l’acceptation de l’envoi par le service mail. Préparer ou annuler le message ne change pas l’état. Un statut déjà modifié par un autre utilisateur pendant l’envoi est conservé. Si la mise à jour de l’état échoue après l’envoi, le mail reste enregistré dans le volet ; vérifier ce journal avant une nouvelle action.

Pour une commande déjà passée par téléphone ou avec une messagerie externe, **Commande passée hors ERP** demande une référence ou explication, conserve l’auteur et l’heure et met à jour le statut dans une transaction. Cette déclaration ne crée pas de faux mail envoyé. Le téléchargement PDF reste disponible sans connexion mail.

## Architecture et vérification

- `src/features/processes/order-followup.js` et `src/styles/order-followup.css` sont chargés à l’ouverture du détail, sans dépendance de démarrage supplémentaire.
- `coco_order_followup` est la façade utilisateur. Les tables `private.coco_order_entries`, `private.coco_mail_accounts` et `private.coco_mail_oauth` sont privées, avec RLS et sans accès direct du navigateur.
- `coco-order-mail` vérifie le jeton Auth, les droits actuels du dossier et l’identité de la boîte. `coco_order_mail_service` est exécutable uniquement par `service_role` ; les jetons OAuth chiffrés n’entrent jamais dans les réponses utilisateur.
- La clé de requête réserve un envoi avant l’appel au fournisseur. Une même clé ne peut envoyer deux messages, ni être réutilisée avec un autre destinataire ou contenu.
- Les tests SQL utilisent une base reconstruite isolée. Les tests des fournisseurs et du navigateur utilisent des réponses simulées et ne contactent aucun client ou fournisseur.

Point de restauration frontend : branche `restore/before-order-followup-release`, commit `93ded8e`. La migration est additive et ne modifie ni ne supprime les historiques existants. Pour désactiver la fonction, republier le frontend précédent et retirer l’accès au connecteur ; conserver les nouvelles tables afin de préserver les notes et les échanges. Ne pas rejouer ou effacer des données métier pour revenir en arrière.
