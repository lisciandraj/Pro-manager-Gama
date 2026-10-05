# Réalisation des améliorations de modules et flux

Périmètre demandé le 5 octobre 2026 : implémentation des modules et des flux. La complétion des produits, fournisseurs et clients reste à la charge du propriétaire. Les paramètres légaux et secrets externes ne sont jamais inventés.

| Action | Périmètre | État et preuve |
| --- | --- | --- |
| A01 | Complétude du périmètre pilote et fournisseurs | Données métier : propriétaire |
| A02 | Recette SRI et moteur privé opérationnel | En cours — validation requise avant déploiement |
| A03 | Paramètres RH / finance confirmés | En cours — validation requise avant déploiement |
| A04 | Mesure frontend, RPC et gestes utilisateur | Implémenté : mesures RPC/ouvertures/actions bornées et P95 sur 7 jours ; fixture metrics. |
| A05 | Fractionnement JS / CSS et lectures à la demande | Implémenté en partie : styles différés (−22 %), Tarifs/Matrice différés ; le découpage du reste du lot initial reste ouvert. |
| A06 | Optimisation SQL / RLS et index ciblés | Index de files, sources et droits ajoutés ; revue des index historiques encore à finaliser. |
| A07 | Sauvegarde complète et exercice de reprise | En cours — validation requise avant déploiement |
| A08 | File de traitements, outbox et supervision | Implémenté : file privée, déduplication, baux, tentatives et reprises ; fixture automation-db. |
| A09 | Envoi réel, statuts et rappels planifiés | Implémenté : outbox Resend, statuts réels, idempotence, préférences ; domaine et clé à configurer. |
| A10 | Règles versionnées et file d'exceptions par dossier | Implémenté : règles immuables, délégation bornée, droits réévalués, affectation/échéance des exceptions. |
| A11 | Réapprovisionnement programmé et brouillons | Implémenté : brouillons par fournisseur avec plafond ; activation de la règle requise. |
| A12 | Réception / achats / factures sans ressaisie | Implémenté et testé : brouillons sur réception, rapprochement/postage atomiques, répétition sans doublon. |
| A13 | Collecte XML puis OCR des factures fournisseurs | XML privé implémenté et testé ; OCR fournisseur non connecté. |
| A14 | Demande → devis → commande sous règles | Implémenté et testé : demande vers devis au résolveur courant ; acceptation vers commande existante préservée. |
| A15 | Activités et relances CRM événementielles | Prochaine activité CRM sans doublon implémentée ; synchronisation des réponses e-mail à compléter. |
| A16 | Parcours Tarifs unifié et marge actualisée | Résolveur commun existant réutilisé ; pagination complète des tarifs spécifiques corrigée. |
| A17 | Picking mobile et inventaires ABC programmés | Picking scanné existant préservé ; génération des comptages ABC programmée ajoutée. |
| A18 | Planification TMS / géocodage sans écran | Planification serveur et historique ajoutés ; géocodage serveur encore ouvert. |
| A19 | Distances routières et fenêtres horaires | Adaptateur ORS privé, cache serveur et contrôles de fenêtres ajoutés ; clé fournisseur à configurer. |
| A20 | Encaissements unifiés et rapprochement sûr | Flux d’encaissement canonique existant conservé ; fixtures finance de validation sans double trésorerie. |
| A21 | Contrôles financiers et clôture par exceptions | Contrôles journaux/factures/stock programmés ajoutés ; clôtures existantes conservées. |
| A22 | IR annuel et variables de paie approuvées | En cours — validation requise avant déploiement |
| A23 | SAV / retour / avoir orchestrés | Réceptions/inspection/crédits existants conservés ; exceptions SLA SAV ajoutées. |
| A24 | Pièces privées, preuves légères et OCR documentaire | En cours — validation requise avant déploiement |
| A25 | Flotte → dépenses / immobilisation / coût tournée | Flotte vers dépense unique implémentée et testée ; coût fiscal à revoir avant postage. |
| A26 | Heures approuvées → coût projet | Heures, approbation, coût projet unique et annulation implémentés et testés. |
| A27 | Pilote B2B et conversion web mesurée | Comptes cloud depuis Contacts, tarifs négociés et Mes documents implémentés ; fixture B2B. |
| A28 | Enquêtes automatiques et apprentissage SAV | Invitation unique après livraison/SAV et arrêt après réponse ajoutés ; dossier SAV unique pour les réponses négatives à une question explicitement configurée ajouté ; apprentissage Knowledge encore ouvert. |
| A29 | Agent Coco | Périmètre remplacé à la demande du propriétaire : conversation conservée, anciennes fonctions retirées, tableau PDF privé avec préfixe RCO ; deux rapports historiques et automatisation hebdomadaire. |
| A30 | Délégations, cycle utilisateurs et traçabilité | Délégations expirantes et révocation effective testées ; anciennes Edge conservées en attente de preuve d’absence d’usage. |
| A31 | Imports / exports suivis et reprenables | Worker classeur et import confirmé différé/reprenable ajoutés ; export Worker, annulation et contrôle de session ajoutés. |
| A32 | KPI / recherche : agrégats et index adaptés | En cours — validation requise avant déploiement |
| A33 | Isolation clients et industrialisation commerciale | Étude, hors construction multi-tenant |

État de livraison : onze nouvelles migrations appliquées dans l’ERP, historique réconcilié et types régénérés ; deux PDF privés importés avec SHA-256 vérifié et tâche hebdomadaire mise à jour. La publication du frontend suit les contrôles GitHub Actions de cette version. Les lignes sans preuve de réalisation restent ouvertes et ne sont pas déclarées terminées.
