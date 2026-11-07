# Simplification des parcours Coco ERP — 7 novembre 2026

Cette livraison rapproche les 30 propositions de simplification des modules
réellement présents dans `lisciandraj/Pro-manager-Gama`. Les points 22 et 23
(Production et Atelier) sont exclus de cette livraison à la demande du
propriétaire : aucun module de fabrication n'est ajouté.

Les mécanismes existants sont conservés lorsqu'ils répondent déjà au besoin.
Les ajouts utilisent les mêmes droits, validations, références, contrôles de
version et moteurs métier. Aucun paiement, envoi de courrier, mouvement de stock
ou accord commercial n'est déclenché à l'ouverture d'une vue.

## Couverture des propositions

| Nº | Proposition | État fonctionnel et parcours |
| --- | --- | --- |
| 1 | Accueil par métier | Dashboard conserve ses priorités actionnables et profils ; le profil proposé par défaut correspond désormais au rôle commercial/logistique/direction. Le menu d'applications reste disponible. |
| 2 | Recherche globale | Existante, avec Ctrl/Cmd+K, adaptateurs métier et ouverture autorisée des dossiers. |
| 3 | Création dans le contexte | Existante depuis les contacts, demandes, devis, projets et besoins de stock ; la réclamation depuis une ligne vendue complète ces points d'entrée. |
| 4 | Retour à une liste conservée | Préférences existantes conservées ; Contacts reprend recherche, page, position et commande de ligne en mémoire, sans stockage persistant de données métier. |
| 5 | Modification directe | Grilles éditables de lignes commerciales et comptages conservées ; pas d'édition directe des états engageants ni des documents validés. |
| 6 | Actions groupées | Sélections et traitements multiples existants dans les espaces opérationnels conservés ; les actions n'accordent aucun droit supplémentaire. |
| 7 | Formulaires minimaux | Sections progressives et valeurs proposées existantes conservées ; ajout des contextes SAV et de la saisie courte des heures. |
| 8 | Brouillons automatiques | Sauvegarde serveur des devis complets après deux secondes sans saisie, sans quitter l'éditeur ni finaliser le document ; statut et avertissement avant abandon des modifications non enregistrées. Voir la section Brouillons. |
| 9 | Parcours au clavier | Ctrl/Cmd+Entrée dans les formulaires partagés, avec validation et verrou de soumission ; `/` cible la recherche visible du tableau. Les confirmations dédiées ne reçoivent pas le raccourci de soumission. |
| 10 | Doublons de contacts | Suggestions pendant la création et ouverture de la fiche existante ; les homonymes ne sont pas interdits. |
| 11 | Historique client unifié | Onglet et raccourci Contacts regroupent documents commerciaux, activités et fichiers récents autorisés. Les limites de lecture restent affichées. |
| 12 | Modèles et copie de devis | Existants dans l'espace Ventes ; tarifs et contrôles de prix conservés. |
| 13 | Continuité commerciale | Conversion et facturation partielle/groupée existantes, sans registre financier parallèle. |
| 14 | Exécution d'une commande | Dossier commercial/logistique/finance et prochaine action existants conservés. |
| 15 | SAV depuis une vente | Réclamation préremplie depuis la ligne visible d'une commande confirmée, après relecture autorisée ; création seulement après validation. |
| 16 | Besoins nets de réapprovisionnement | Calcul et couverture serveur existants conservés : stock, réservations, brouillons et reliquats d'achat. |
| 17 | Commandes par fournisseur | Regroupement et création atomique de brouillons depuis les besoins existants conservés. |
| 18 | Réception sans ressaisie | Reliquats déjà proposés ; ajout de « Réceptionner et suivant », avec reprise de la même clé après erreur. Le dossier suivant s'ouvre sans être réceptionné. |
| 19 | Scan des mouvements | Moteurs de scan et validation d'article/emplacement existants conservés. |
| 20 | Préparation par emplacement | Tri de préparation et contrôle des quantités par scan existants conservés. |
| 21 | Inventaires ciblés | Périmètres et cycles existants ; ajout des vues À compter/Écarts et d'Entrée pour enregistrer puis passer à la ligne suivante. Le comptage aveugle ne révèle pas le stock théorique. |
| 22 | Ordres de fabrication | Hors périmètre, décision du propriétaire. |
| 23 | Vue d'atelier | Hors périmètre, décision du propriétaire. |
| 24 | Factures fournisseurs et OCR | Extraction et contrôle achat/réception existants ; échéance proposée et nouvelle revue après correction ajoutées. La lecture ne vaut pas validation fiscale. |
| 25 | Banque en série | Suggestions et « Rapprocher et suivant » existants ; recherche au clavier sans validation accidentelle et accès filtrés complétés. |
| 26 | Relances regroupées | Préparation consolidée par identité client, montant et détail des factures admissibles. Nouvelle lecture des exclusions avant préparation. Aucun message envoyé par cette action. Migration additive requise. |
| 27 | Temps depuis une tâche | Action depuis liste, Kanban et fiche ; ajout aux heures cumulées avec contrôle de version. Aucun coût approuvé ni salaire n'est créé par cette saisie. |
| 28 | Validations RH | File en attente accessible aussi aux RH/admin avec type, fractions de journée, jours ouvrés et solde par année ; périmètre N+1 conservé. |
| 29 | Indicateurs actionnables | Compteurs reliés aux détails filtrés et à la période affichée ; les statistiques descriptives ouvrent leur valeur, source et méthode. Un indicateur indisponible reste inactif, distinct d'un vrai zéro. |
| 30 | Modèles d'accès | Quatre rôles de base et modèles d'entreprise existants conservés ; ajout d'un aperçu des modules dans Configuration → Utilisateurs → Profils et modules. L'aperçu ne change aucun compte. |

## Brouillons

La sauvegarde automatique porte sur les devis modifiables et valides. Elle ne
finalise pas le devis et ne l'envoie pas. Une demande n'est pas convertie
automatiquement en devis. Les brouillons incomplets demandent encore une
correction avant leur enregistrement métier. Les formulaires financiers,
fiscaux, RH et de stock conservent leur validation explicite.

Les écritures automatiques et manuelles sont sérialisées. L'éditeur reprend
l'identifiant et la révision renvoyés par le serveur, conserve les modifications
effectuées pendant une sauvegarde et suspend l'automatisme après une erreur ou
un conflit. Aucune donnée métier n'est placée dans le stockage du navigateur.
Les brouillons enregistrés se reprennent depuis la liste Ventes ; les champs
incomplets ne sont pas récupérables après fermeture forcée du navigateur.

## Vérification

Les scénarios navigateur emploient des fixtures locales ; les tests SQL des bases
isolées. Ils ne créent aucun dossier de production. La vérification porte sur les
chemins utilisateurs, la conservation des saisies après erreur, les reprises,
les droits, le changement de compte et l'absence de mutation du dossier suivant.

Les contrôles communs restent ceux de `npm run update`, complétés par les suites
Contacts/SAV, achats/inventaires, Projets/RH, Comptabilité/Dashboard, formulaires,
recherche globale et profils. La construction régénère les sorties historiques ;
ces fichiers ne sont jamais modifiés manuellement.

Les tests des nouveaux parcours sont ajoutés au contrôle de publication Pages.
La validation Node couvre 765 cas exécutables ici ; deux scénarios historiques
de concurrence entre sessions PostgreSQL nécessitent leur base dédiée et sont
ignorés localement. Les contrôles de génération et d'architecture sont relancés
sur les sources stabilisées. Six captures de fixtures PC/téléphone vérifient
réception, inventaire et aperçu des rôles sans débordement de page.

Les gains de clics et de temps ne sont pas encore mesurés en utilisation réelle.
Mesurer des dossiers comparables, par rôle : durée jusqu'à une opération
correcte, actions manuelles, changements d'écran, corrections et réussite sans
aide. Les scénarios de réception, comptage et temps ne nécessitent plus de
retour à une liste générale entre deux opérations successives.

## Livraison et retour arrière

1. Construire et valider les sources, puis pousser la branche de travail et
   conserver les contrôles CI avant la fusion/publication.
2. La migration `20261107170411_consolidated_collection_preview.sql` a été appliquée
   sur `mknsaibrewksgomuslev` sous la version distante `20261107191544`. Son empreinte
   est enregistrée dans `supabase/migration-history.json`. Les trois signatures,
   droits et gardes ont passé le [contrôle des métadonnées](../../scripts/verify-collection-preview.sql).
   Elle ajoute une lecture contrôlée, sans mise à jour des factures ni des
   préférences de relance. Ne pas rejouer les autres migrations historiques.
3. Publier l'artefact ERP validé selon la [procédure Pages](pages-publication.md).
   Un commit sur la branche de travail ne prouve pas une mise en production.
4. Pour revenir en arrière, republier le précédent artefact. La nouvelle lecture
   serveur peut rester installée ; aucun historique métier n'est supprimé.

Voir aussi [Ventes](../modules/sales-workflow.md), [Contacts](../contacts.md),
[Stock](../modules/stock.md), [Projets](../modules/projects.md),
[RH](../modules/hr.md) et [extensions commerciales](../commercial-planning.md).
