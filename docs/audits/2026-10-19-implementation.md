# Mise en œuvre des constats de l’audit

Autorisation reçue : « Implémente tous les points de l’audit ». Base examinée : `6746cec99c5ed03449a8276560eee3081e2db09c`. Ce document distingue le code préparé de son activation et de la validation en conditions réelles. La présentation GAMA, les identifiants publics et les moteurs métier sont conservés.

| Constat | Mise en œuvre | Validation et limite |
|---|---|---|
| PERF-01 | Projection paginée du catalogue avant traitement des photos ; un seul calcul matérialisé au bootstrap ; contrôle d’empreintes et SQL de retour arrière. | Réponses identiques et droits vérifiés en base isolée ; mesure après livraison encore nécessaire. |
| PERF-02 | Affichage par lots de 30 jusqu’à 100 ; photos à proximité de l’écran ; deux requêtes de 24 maximum ; annulation, dédoublonnage et cache borné. | Tests de réponses retardées, changement de compte et peinture de chaque lot ; parcours PC/mobile en CI. |
| PERF-03 | Minification des identifiants locaux dans les deux bundles initiaux et du cœur ESM ; aucune nouvelle infrastructure. | Budget de démarrage mesuré. Les langues conservent leurs catalogues complets ; aucune promesse de temps CPU sans trace navigateur. |
| PERF-04 | Déduplication des lectures de notifications, pause lorsque l’onglet est masqué, limite sur les rafraîchissements de badge et recul progressif après erreur. | Test du nombre de requêtes, erreurs et changement de session ; égalité badge/snapshot déjà vérifiée par rôle. |
| PERF-05 | Conservation de la correction récente des historiques ; benchmark isolé et tests des restrictions. | Pas de nouvel index sans preuve de bénéfice. Les durées de laboratoire ne prouvent pas l’ouverture de l’écran en production. |
| SEC-01 | Enrôlement MFA accessible, rappel administrateur et activation serveur persistante après validation d’un facteur ; suppression du dernier facteur découragée dans l’interface. | Tests du refus AAL1 après activation, même si le facteur est supprimé. Chaque titulaire doit enrôler son authentificateur ; aucune activation forcée ne bloque les comptes non préparés. |
| SEC-02 | Neutralisation des formules dans le CSV d’audit en conservant les nombres négatifs et l’échappement CSV. | Tests de l’export réel et des permissions ; ouverture dans Excel/LibreOffice non exécutée ici. |
| SEC-03 | Preuves TMS chiffrées par compte, purge des tournées à la déconnexion et à expiration, suppression du déverrouillage, conservation des preuves en attente et récupération après authentification. | Tests cryptographiques, refus entre acteurs, modification du ciphertext et récupération ; la session d’onglet permet les rechargements hors ligne. Anciennes files à migrer lors de la prochaine connexion de leur propriétaire. |
| REL-01 | Deux resets archivés hors des migrations courantes ; empreintes conservées ; registre distant photographié ; deux migrations distantes récupérées ; manifeste et précontrôle de livraison. | Refus d’un registre inconnu ou modifié. Les 70 correspondances historiques ne sont pas certifiées par leur seul nom ; pas de réparation aveugle du registre. Une copie restaurée reste nécessaire pour clore la réconciliation. |
| REL-02 | Configuration de protection de main et script avec sauvegarde de l’état préalable ; contrôles CI ajoutés. | Accès d’administration GitHub refusé par le connecteur (HTTP 403). La règle ne peut pas être activée avec cette connexion. |
| OPS-01 | Export chiffré en flux de PostgreSQL et Storage, inventaire et empreintes, configurations versionnées, procédure d’exercice et retour arrière. | Précontrôle exécuté ; identifiants de sauvegarde, clé age et hôte d’exécution manquants. Ni planification réelle ni restauration métier attestée. |
| OBS-01 | SHA du HTML publié, contexte navigateur/PWA/retour de module, phases utiles, bibliothèque officielle Web Vitals 6.2.3, dédoublonnage des mesures de visite, seuils d’échantillon pour les percentiles. | Validation des champs et absence d’accès direct aux métriques. Collecte terrain à observer après livraison ; largeur de fenêtre explicitement identifiée comme approximation de l’appareil. |
| AGENT-01 | Approbation ERP sans client OAuth, avec MFA fraîche postérieure à la proposition ; digest, acteur, session et expiration ; une vérification pour une proposition ; exécuteur privé inaccessible directement. | Refus de l’auto-approbation et du digest modifié ; conservation des contrôles de stock, des validations ERP et des reçus idempotents. Les écritures de l’agent exigent désormais un authentificateur. |

## Ordre de livraison

1. Vérifier la branche et les contrôles de CI ; ne pas confondre une alerte d’outil avec un défaut exploitable.
2. Relire le registre distant avec ses empreintes et comparer au manifeste. Appliquer uniquement les trois migrations explicitement revues, séparément des archives historiques. Sauvegarder leurs définitions remplacées avant chaque action.
3. Publier l’interface ERP, la fonction MCP et le site Cloudflare en conservant leur SHA. Une mise à jour GitHub Pages ne met pas à jour Cloudflare Pages.
4. Vérifier publiquement le catalogue et le refus sans authentification. Utiliser uniquement des comptes et données de recette pour les preuves TMS, mouvements et doubles exécutions.
5. Enrôler les administrateurs avec un second facteur de récupération ; configurer la règle GitHub depuis un compte ayant le droit Administration ; fournir un coffre et un hôte privé pour la sauvegarde puis réaliser l’exercice.

## Retours arrière et risques

Le catalogue possède un retour exact de fonction avec garde d’empreinte. Le code peut revenir à un artefact précédemment validé. Ne pas supprimer les clés TMS ou les tables de reçus : des preuves peuvent en dépendre. Une désactivation de l’écriture Agent est préférable à la remise en service de l’auto-confirmation. Le chiffrement local ne protège pas un appareil laissé déverrouillé ou compromis ; la déconnexion demeure nécessaire sur un appareil partagé.

Références techniques : documentation Supabase MFA et sauvegardes, PostgreSQL 17, documentation officielle `web-vitals` du paquet épinglé, API GitHub de protection de branche. Les versions et restrictions de l’audit initial restent applicables. Aucun changement de plan payant ni nouvel abonnement n’est nécessaire pour ces correctifs.
