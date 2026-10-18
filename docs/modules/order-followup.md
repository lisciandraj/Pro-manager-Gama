# Historique et suivi des dossiers

Les modules Ventes, Achats et TMS affichent un volet **à droite**, intitulé **Historique du module** dans les vues générales et **Historique du dossier** dans une fiche. Le titre suit le dossier sélectionné, y compris lors du choix d’une livraison dans le TMS. Sur téléphone, le même volet s’ouvre depuis son bandeau fixé en bas à droite. Les couleurs Coco sont conservées. Les fiches devis, commandes clients et commandes fournisseurs montrent leurs notes et événements. Le TMS dispose d’un sélecteur de livraison et d’une boîte de propositions du module. Les listes de devis et commandes et le module Achats présentent aussi les propositions qui n’ont pas encore de dossier.

Sur téléphone, le volet ouvert utilise la hauteur visible, y compris lorsque le clavier réduit l’écran. Son bandeau et sa fermeture restent visibles ; les messages et notes défilent dans une seule zone, sans défilement imbriqué dans les bulles. Fermer puis rouvrir le volet conserve une note non enregistrée. La revue d’une proposition garde son en-tête et ses boutons de vérification, validation et annulation visibles pendant le défilement du contenu.

Chaque bulle indique l’action ou la note, le nom de l’auteur et la date du serveur. L’ordre est décroissant : les éléments les plus récents sont en haut, les plus anciens en bas, dans les modules et les dossiers. Cet ordre reste identique après filtrage, actualisation et chargement des pages précédentes. La photo vient du portrait du salarié associé au compte, s’il existe ; sinon ses initiales s’affichent. Une action historique sans auteur reste signalée comme telle. La photo ne donne accès à aucune autre donnée RH.

Les actions identiques d’une même transaction sont réunies dans une bulle avec un compteur et la liste des références concernées. Une réservation de plusieurs produits montre les références, noms et quantités ; les allocations d’un même produit sont additionnées. Les cinq premières références sont visibles, les suivantes se déplient dans la bulle. Le regroupement respecte le dossier, l’auteur, l’étape, l’état et l’horodatage serveur exact ; une autre opération, une note ou une proposition conserve sa propre bulle. Les événements du dossier sont regroupés avant pagination, même lorsqu’une opération dépasse cinquante produits. Les journaux d’origine restent intacts.

Les bulles conservent les accès aux documents et modules liés : demande client, CRM, commande, devis, préparation, stock, livraison, facturation et retours selon l’événement et les droits du compte. Les liens ouvrent le dossier concerné lorsqu’il existe ; les accès généraux ouvrent le module. Les références sont une projection limitée des journaux autorisés, sans exposer les données brutes d’audit.

Dans **Achats → Historique du module**, chaque nouveau brouillon créé par le réapprovisionnement automatique minimum/maximum ajoute une action **Brouillon d’achat automatique**. Elle conserve la référence, le fournisseur, les articles et quantités préparées, ainsi que le stock physique et les seuils au moment de la création. Le compte ayant délégué l’automatisation et sa photo restent associés à la trace, explicitement présentée comme automatique. **Ouvrir le brouillon** recharge les achats et ouvre la commande concernée. La trace est enregistrée dans la transaction du brouillon, même lorsque l’ERP est fermé ; un nouveau contrôle sans création ou la reprise du même traitement ne crée aucune bulle supplémentaire. Les anciennes créations ne sont pas antidatées ni ajoutées rétroactivement.

Les événements du dossier commercial se suivent du devis jusqu’à la commande, aux réservations, à la préparation, aux expéditions, aux preuves, à la facturation et au paiement. Les notes suivent le lien devis → commande → livraison. Les achats reprennent leurs étapes de commande, réception, stock, facture et paiement fournisseur. Le filtre d’étape conserve les étapes autorisées ; les étapes financières restent masquées pour les profils sans accès. Les anciens événements se chargent par pages. Le TMS capture aussi les modifications futures de sa fiche.

## Analyse des mails par Agent Coco

La connexion Gmail/Outlook dans Supabase est retirée. Coco ne conserve plus de jetons de boîte mail et l’ancien endpoint `coco-order-mail` répond `410 MAIL_CONNECTOR_REMOVED`. Les notes et archives de messages existantes sont conservées.

ChatGPT utilise sa propre messagerie connectée et un déclencheur sur les nouveaux messages Gmail. L’activation concerne une boîte vérifiée correspondant exactement à un compte ERP actif. Une connexion dans ChatGPT ne connecte pas les boîtes des autres utilisateurs. Un nouvel utilisateur doit connecter sa propre boîte dans ChatGPT et faire activer son propre déclencheur.

Le déclencheur réveille ChatGPT, qui relit le message réel, écarte les notifications sans intérêt métier puis propose une action. Il ne s’agit pas d’une garantie de traitement instantané : un délai du service est possible. L’ERP actualise la discussion toutes les quinze secondes lorsque la fiche est visible et qu’aucun éditeur n’est ouvert.

L’assistant s’affiche sous le nom **Agent Coco**, y compris pour les analyses déjà enregistrées sous le nom ChatGPT. Ce changement de présentation conserve les auteurs humains et les données historiques. Une analyse devient une **note Agent Coco** et une proposition **À valider**. La note indique le résumé et le mail source. Les références ambiguës restent dans les propositions du module. Aucun client ni produit n’est inventé, aucun devis n’est envoyé ou accepté et aucun paiement ou mouvement de stock n’est exécuté par l’analyse.

Pour une demande de devis, **Examiner la proposition** permet de vérifier ou corriger le client, les produits, les quantités et l’adresse. **Vérifier la proposition** relit les prix et taxes de l’ERP. **Valider l’action** crée un seul devis en brouillon par le moteur commercial existant. Si les prix changent ou si la revue expire, une nouvelle vérification est nécessaire. Le brouillon conserve une note de l’analyse et une note de validation avec son auteur. **Ouvrir le brouillon** permet de poursuivre le dossier.

Les autres demandes d’achat ou de livraison deviennent des propositions de suivi à confirmer comme note ; l’utilisateur poursuit ensuite l’opération dans le module. **Refuser** conserve aussi une note de décision. Les doublons de message et les doubles validations sont neutralisés côté serveur.

Le volet **Analyse par Agent Coco → Suspendre l’analyse** désactive immédiatement le dépôt de nouvelles propositions pour sa boîte. L’automatisation peut également être suspendue dans ChatGPT. Les propositions existantes restent consultables.

## Courriers sortants

Les commandes fournisseurs permettent de préparer un mail externe et de télécharger leur PDF. L’ouverture de Gmail ou Outlook ne prouve pas l’envoi et ne change pas l’état de la commande. **Commande passée hors ERP** reste disponible avec une référence ou explication et une trace de l’auteur.

## Architecture et vérification

`src/features/processes/order-followup.js` et `src/styles/order-followup.css` sont chargés à la demande. `coco_dossier` contrôle authentification, MFA, module, dossier et action. Les chauffeurs restent limités aux livraisons qui leur sont assignées. `coco_mail_bridge` est réservé au service de confiance ChatGPT/Supabase ; il dépose uniquement des propositions en attente, sans exécuter d’action métier. Les tables privées ont RLS et aucun accès direct du navigateur.

Le [guide du relais ChatGPT](../development/order-mail-setup.md) décrit l’activation, le contrat et les limites. Les tests SQL sont isolés et les tests navigateur simulent les services ; aucun mail réel n’est envoyé pendant ces tests.

Les événements complémentaires de **Piste d’audit** rattachés au module ou au dossier apparaissent dans le même fil, avec une mention d’origine, les références, quantités et montants disponibles. Les événements déjà représentés par le parcours (réception d’achat, livraison, facture ou paiement) ne créent pas une seconde bulle. Les validations et autres événements manquants rejoignent leur dossier par les liens métier réels. Les droits de lecture de la piste d’audit restent exigés ; voir le [contrat de l’historique commun](module-history.md#piste-daudit-dans-les-historiques).
