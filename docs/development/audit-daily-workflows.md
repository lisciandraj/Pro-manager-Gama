# Parcours quotidiens — livraison du 20 octobre 2026

Cette livraison applique les cinq améliorations prioritaires de l’audit Coco ERP. La facturation SRI est exclue. Elle conserve les chartes distinctes de l’ERP et du catalogue, les références des documents, les calculs de prix et les commandes métier existantes. Aucun service payant ni dépendance d’exécution supplémentaire n’est ajouté.

## Changements utilisables

| Parcours | Avant | Après | Contrôle conservé |
| --- | --- | --- | --- |
| Recherche du catalogue | Les réponses périmées sont ignorées, mais les requêtes publiques continuent ; l’échec ne fournit pas de reprise locale | Annulation des requêtes publiques remplacées ; bouton de reprise avec recherche et panier conservés ; liens vers `/b2b.html` | Les prix connectés restent propres au compte ; changement de compte efface les anciens résultats. Le client Supabase connecté conserve sa protection par génération, sans prétendre annuler sa requête réseau. |
| Prix à vérifier | Recherche manuelle des produits de faible prix | Filtre administratif « prix ≤ 0,05 USD », avant pagination, prix affiché | Candidat à vérifier, pas erreur avérée. Aucune modification ou dépublication automatique. Vérifier aussi l’unité commerciale dans Produits. |
| Exceptions | 100 premières exceptions ; la fenêtre de suivi ne permet pas de choisir le responsable | Pagination serveur de 50 ; filtres « mes exceptions », « sans responsable », « échéance dépassée » ; responsable, prochaine action et date préremplis | Droits du dossier conservés ; seul l’administrateur affecte une autre personne interne active ; refus d’un suivi périmé/résolu ; historique de l’auteur et du dossier. Une affectation ne confère aucun droit. |
| Réapprovisionnement | La liste manuelle affiche les besoins de prévision positifs ; les produits sous minimum mais couverts sont peu explicites | Détail repliable de couverture min/max : physique, brouillons, restant à recevoir, manque jusqu’au maximum, commandes associées et fournisseur manquant | Réutilisation de `stock_minmax_replenishment_rows`. Prévision de consommation et min/max restent distincts. Achats partiels comptés uniquement pour leur reliquat. Pas de commande supplémentaire créée par cette vue. |
| Adresses | Accès par le dossier puis son onglet Relations ; sortie du devis pour compléter une adresse | Accès direct depuis Contacts, devis, commande et planification TMS ; retour au devis avec liste actualisée | Aucun remplacement automatique de l’adresse saisie ou du cliché historique d’une commande/livraison. Enregistrement par le RPC existant avec contrôle de version. |
| Banque | Huit filtres toujours présentés ; retour à la liste après chaque rapprochement | État, compte et recherche visibles ; cinq filtres avancés repliables ; action « Rapprocher et suivant » | Choix humain pour chaque ligne ; même clé de requête en cas de reprise ; contrôle des soldes, droits et atomicité existants ; aucun choix automatique sur la ligne suivante. |

La migration corrige aussi une ambiguïté SQL préexistante entre la variable `key` et la colonne `automation_exceptions.key`, révélée par le test réel d’affectation en base isolée.

## Accès et reprise

Dans « Sécurité de mon compte », un administrateur autorisé à voir les utilisateurs peut consulter les comptes administrateurs actifs et l’état de leur authentificateur. Cette consultation n’enrôle personne, ne change aucun rôle et n’instaure aucun nouveau blocage. Chaque personne doit valider son propre code ; le responsable décide des rôles utiles. Le bandeau d’accueil précédemment retiré n’est pas réintroduit.

La sauvegarde complète reste une condition opérationnelle non satisfaite par du code seul. Le contrôle à blanc de `scripts/backup-coco.py` ne trouve ni les quatre paramètres de connexion/chiffrement, ni `pg_dump`/`age` sur l’hôte de cette intervention. Le script et la procédure [de reprise](../operations/recovery.md) existent déjà. Aucune sauvegarde de production, restauration Auth/Storage ou garantie RPO/RTO n’est annoncée. La restauration du schéma et les scénarios métier isolés ne remplacent pas cet exercice.

## Validation et suivi

- Tests de base isolée : filtrage au-delà de 100 exceptions, affectation concurrente, interdiction d’affectation externe, visibilité de l’historique selon le dossier, revue MFA réservée aux administrateurs, prix filtrés avant pagination, reliquats d’achat, absence d’accès achats pour le magasinier.
- Tests de catalogue : réponse tardive, changement de compte, conservation des premières cartes après erreur et reprise accessible.
- Parcours d’interface : Contacts, Banque, Stock, administration du site ; le rapprochement enchaîné garde une validation explicite et une clé stable après erreur.
- Compilation et contrôles de reproductibilité obligatoires. Vérifier séparément le SHA de GitHub Pages et celui de Cloudflare Pages ; la publication de l’un ne publie pas l’autre.

Les gains de temps ne sont pas encore mesurés. Relever avant/après sur dix dossiers comparables : durée médiane d’un devis avec adresse secondaire, nombre de retours à la liste pour dix lignes bancaires, proportion d’exceptions sans responsable, erreurs/reprises de recherche, achats en double. Cibles fonctionnelles : aucun écrasement concurrent, aucune création en double, aucun accès entre clients, aucun retour à la liste nécessaire entre deux rapprochements successifs dans le résultat courant.

## Déploiement et retour arrière

1. Appliquer uniquement la migration `audit_daily_workflows` après comparaison du registre distant et des fonctions concernées. Elle ajoute des métadonnées de lecture et un historique ; elle ne réécrit aucune donnée métier et ne change aucune règle SRI.
2. Publier les sources compilées après les tests. Les anciens clients restent compatibles : nouveaux paramètres facultatifs, champs de retour supplémentaires et RPC de revue administrative indépendant.
3. En cas d’anomalie d’interface, republier le précédent artefact ERP/Cloudflare. Garder la migration et l’historique des nouvelles affectations : aucune restauration de base n’est nécessaire pour revenir aux anciens écrans.
4. Si un défaut serveur est confirmé, corriger en avant par une migration ciblée après reproduction isolée. Pour neutraliser l’affectation, retirer temporairement son accès dans le code ; ne pas supprimer l’historique, modifier les paiements ni remettre en circulation un ancien document.

Les prix à confirmer, le fournisseur absent et les comptes administrateurs à conserver demandent une décision métier ; cette livraison donne les accès pour les traiter sans inventer ces décisions.
