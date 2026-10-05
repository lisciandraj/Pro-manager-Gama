# Automatisations et flux

État : 5 octobre 2026. Sources : `src/features/processes/`, migrations `20261005145609` à `20261005165044`. Les traitements sont exécutés sur le serveur et continuent quand l’ERP est fermé.

Configuration → **Automatisations et exceptions** permet de consulter les règles, traitements, tentatives et dossiers à traiter. Le Centre de notifications propose le même suivi. Une exception peut être affectée avec une prochaine action et une échéance. Les droits de chaque module et le périmètre financier continuent de filtrer les résultats.

Les contrôles opérationnels et financiers sont actifs à l’installation. Les actions métier exigent une activation explicite par un administrateur, des plafonds et une délégation de 90 jours maximum. Chaque modification crée une version immuable. Les traitements d’une version remplacée sont annulés ; un utilisateur désactivé ou privé de ses droits ne peut plus servir de délégataire. Une délégation ne permet pas de signer une réception, confirmer une donnée légale ou émettre un document SRI.

| Règle | Résultat | Validation conservée |
| --- | --- | --- |
| Réapprovisionnement | Brouillons de commandes, groupés par fournisseur | Coût, fournisseur, délai et plafond ; aucun mouvement physique |
| Inventaires ABC | Comptages A/30, B/90 et C/180 jours | Entrepôt configuré, absence de comptage ouvert ; comptage physique requis |
| Demande vers devis | Devis éditable au prix courant négocié | Client/produit complets, adresse et plafond ; acceptation explicite |
| Devis accepté vers commande | Flux transactionnel existant | Conditions, crédit et prix validés ; aucune seconde commande |
| CRM | Prochaine activité sans doublon | Propriétaire actif et absence d’activité ouverte |
| Planification TMS | Plan de journée et historique des versions | Tournées parties et verrous manuels conservés ; GPS manquant signalé |
| Réception vers facture | Brouillon sur les quantités reçues restant à facturer | Document fournisseur réel, rapprochement et comptabilisation explicites |
| Flotte vers dépenses | Dépense en brouillon unique par coût | Justificatif, taxes et paiement à vérifier |
| Heures projet | Coût de personnel unique après approbation | Salarié autorisé, coût horaire et preuve d’approbation ; aucune écriture de paie |
| Suivi SAV | Dossier SLA dépassé affectable | Résolution, inspection physique et crédit existants |
| Relances et enquêtes | Messages préparés puis envoyés par le fournisseur configuré | Préférences actives, droits et délégation actuels, source non résolue |
| Satisfaction négative | Dossier SAV unique associé à la réponse client | Question de satisfaction explicitement choisie ; réponses anonymes et quiz exclus |
| Imports confirmés | Application différée du lot déjà préparé | Confirmation du lot, règle active du même administrateur, contrôles ligne par ligne |

## Achats et dépenses

Comptabilité → Achats → **Réceptions et factures à vérifier** ouvre les brouillons. Corriger les champs d’après le document réel, enregistrer, puis valider les lignes de réception et les montants. Le serveur poste la facture, approuve le rapprochement et crée son écriture dans une seule transaction. La même clé retournée après une interruption ne poste pas deux fois. Un brouillon ne peut pas être payé.

**Importer XML fournisseur** retrouve exactement un fournisseur actif par RUC, contrôle l’acquéreur si son RUC est renseigné, les montants, la devise et les doublons, puis conserve l’original privé. Les DTD et entités externes sont refusées. La signature et l’autorisation SRI restent à vérifier ; le brouillon ne les certifie pas. Les taxes autres que l’IVA, les pourboires et les documents incompatibles sont signalés à vérifier. L’OCR n’est pas connecté dans cette version.

Les dépenses préparées depuis Flotte exigent la case de vérification de la source avant comptabilisation. Les heures se saisissent depuis le détail Projet ; l’approbation nécessite aussi les droits RH. L’annulation annule le coût projet associé.

## Envois et préférences

**Mails à envoyer** présente les relances et invitations de questionnaire préparées par les règles autorisées. Le client active séparément ses rappels et enquêtes dans **Mes préférences** ; ils sont désactivés par défaut. Les droits, délégations, préférences, destinataire et document source sont contrôlés à la préparation et à l’ouverture du brouillon. Une facture payée, une enquête répondue, un destinataire modifié ou une préférence retirée annule le brouillon périmé.

**Préparer le mail** ouvre le destinataire, l’objet et le texte. Gmail, Outlook.com, Outlook / Microsoft 365 et l’application mail ouvrent un message prérempli sans clé API. L’utilisateur vérifie puis clique sur Envoyer dans sa boîte mail. Il coche ensuite **J’ai envoyé ce message depuis ma boîte mail** et confirme dans Coco. L’ouverture du brouillon ne marque aucun envoi. L’état **Envoyé · confirmation manuelle** conserve l’auteur et la date ; il ne certifie pas une livraison ou une lecture. Les confirmations répétées restent idempotentes.

Resend est retiré du parcours actif. Son fournisseur est désactivé, les anciens appels serveur sont neutralisés et le cron d’envoi est supprimé. Les preuves historiques de livraison sont conservées. Aucun mail n’est envoyé automatiquement par Coco. L’envoi Gmail de l’automatisation hebdomadaire Agent Coco reste distinct.

## Performances et imports

**Voir les performances mesurées** calcule le P95 des mesures réelles sur sept jours, par module, opération, appareil et réseau. Les échantillons ne contiennent ni paramètres de formulaire, document, URL, token ou texte d’erreur. Les écritures sont bornées et limitées ; conservation quatorze jours. Sans échantillons, aucun P95 n’est inventé. La navigation mesure l’ouverture, les RPC leur réponse ; cela ne remplace pas une mesure de rendu de chaque composant.

Les styles des grands modules se chargent à l’ouverture et les Tarifs/Matrice sont différés. Les tarifs spécifiques lisent toutes les pages. La lecture et la génération des classeurs s’effectuent dans des Workers locaux ; elle est interrompue lors d’un nouveau fichier ou d’un changement de session. L’import en arrière-plan s’active pour un lot explicitement confirmé et ses états sont consultables dans les traitements. Les imports réussis restent idempotents et les lignes en erreur se corrigent avant reprise.

## Tournées et rapports

**Navigation Waze** ne nécessite aucune clé API. Chaque arrêt de l’écran chauffeur et du planning ouvre Waze à ses coordonnées GPS, ou recherche son adresse. Le bouton de tournée ouvre le prochain arrêt restant, puis le retour au dépôt lorsqu’il est prévu. Le navigateur utilise le lien officiel HTTPS Waze ; sur téléphone il ouvre l’application installée.

Coco conserve son organisation des arrêts, ses distances estimées et sa carte. Les liens Waze ne fournissent aucune matrice de distances ni temps de trafic à l’ERP. Les kilomètres et minutes vérifiés dans Waze se saisissent dans le planning existant, avec leur source ; les fenêtres de livraison et les validations de départ restent contrôlées. Les horaires routiers déjà vérifiés sont conservés. OpenRouteService est désactivé et son cron/circuit réseau neutralisé.

Référence : [Waze Deep Links](https://developers.google.com/waze/deeplinks).

[Agent Coco](modules/coco-intelligence.md) conserve la conversation et archive les rapports hebdomadaires PDF sous le préfixe RCO. La tâche hebdomadaire existante ajoute l’archivage du PDF à son envoi par mail, avec déduplication de la période.

## Vérification

Les fixtures `automation-db`, `automation-flows-db`, `supplier-xml-metrics-db`, `message-outbox-db` `background-import-db`, `survey-feedback-db`, `tms-roads-db` et `agent-coco-reports-db` restaurent les migrations dans une base isolée. Les fixtures vérifient qu’aucune requête aux anciens fournisseurs n’est émise. Aucune clé réelle ni communication externe n’est utilisée. Les tests B2B vérifient prix, association explicite, suspension, documents et téléchargements entre entreprises. La validation réelle du domaine e-mail, du signataire SRI et des appareils de scan reste liée à leur configuration.
