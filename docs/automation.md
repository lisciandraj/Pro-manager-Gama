# Automatisations et flux

État : 5 octobre 2026. Sources : `src/features/processes/`, migrations `20261005145609` à `20261005161024`. Les traitements sont exécutés sur le serveur et continuent quand l’ERP est fermé.

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
| Imports confirmés | Application différée du lot déjà préparé | Confirmation du lot, règle active du même administrateur, contrôles ligne par ligne |

## Achats et dépenses

Comptabilité → Achats → **Réceptions et factures à vérifier** ouvre les brouillons. Corriger les champs d’après le document réel, enregistrer, puis valider les lignes de réception et les montants. Le serveur poste la facture, approuve le rapprochement et crée son écriture dans une seule transaction. La même clé retournée après une interruption ne poste pas deux fois. Un brouillon ne peut pas être payé.

**Importer XML fournisseur** retrouve exactement un fournisseur actif par RUC, contrôle l’acquéreur si son RUC est renseigné, les montants, la devise et les doublons, puis conserve l’original privé. Les DTD et entités externes sont refusées. La signature et l’autorisation SRI restent à vérifier ; le brouillon ne les certifie pas. Les taxes autres que l’IVA, les pourboires et les documents incompatibles sont signalés à vérifier. L’OCR n’est pas connecté dans cette version.

Les dépenses préparées depuis Flotte exigent la case de vérification de la source avant comptabilisation. Les heures se saisissent depuis le détail Projet ; l’approbation nécessite aussi les droits RH. L’annulation annule le coût projet associé.

## Envois et préférences

**Configurer les envois** connecte une clé Resend et un expéditeur sur un domaine vérifié. La clé est conservée dans Vault et n’est jamais renvoyée au navigateur. Aucun fournisseur n’est configuré par la migration. Le client active séparément ses rappels et enquêtes dans **Mes préférences** ; les deux sont désactivés par défaut.

Le cron contrôle à nouveau droits, règle, préférence, adresse et source avant chaque envoi. Les états distinguent attente, transmission, acceptation fournisseur, livraison, rebond et résultat incertain. Une acceptation HTTP ne signifie pas livraison. Les reprises utilisent la même clé et le même message ; elles s’arrêtent avant expiration de la fenêtre d’idempotence du fournisseur. Un résultat ambigu exige consultation, sans nouvelle émission automatique. Les invitations de questionnaire sont uniques par client et questionnaire, et cessent après réponse ou révocation.

Références techniques : [pg_net](https://supabase.com/docs/guides/database/extensions/pg_net), [idempotence Resend](https://resend.com/docs/dashboard/emails/idempotency-keys), [statut d’un envoi](https://resend.com/docs/api-reference/emails/retrieve-email).

## Performances et imports

**Voir les performances mesurées** calcule le P95 des mesures réelles sur sept jours, par module, opération, appareil et réseau. Les échantillons ne contiennent ni paramètres de formulaire, document, URL, token ou texte d’erreur. Les écritures sont bornées et limitées ; conservation quatorze jours. Sans échantillons, aucun P95 n’est inventé. La navigation mesure l’ouverture, les RPC leur réponse ; cela ne remplace pas une mesure de rendu de chaque composant.

Les styles des grands modules se chargent à l’ouverture et les Tarifs/Matrice sont différés. Les tarifs spécifiques lisent toutes les pages. La lecture des classeurs s’effectue dans un Worker local ; elle est interrompue lors d’un nouveau fichier ou d’un changement de session. L’import en arrière-plan s’active pour un lot explicitement confirmé et ses états sont consultables dans les traitements. Les imports réussis restent idempotents et les lignes en erreur se corrigent avant reprise.

## Vérification

Les fixtures `automation-db`, `automation-flows-db`, `supplier-xml-metrics-db`, `message-outbox-db` et `background-import-db` restaurent les migrations dans une base isolée. Vault et pg_net sont simulés seulement dans ces fixtures : aucune clé réelle ni communication externe n’est utilisée. Les tests B2B vérifient prix, association explicite, suspension, documents et téléchargements entre entreprises. La validation réelle du domaine e-mail, du signataire SRI et des appareils de scan reste liée à leur configuration.
