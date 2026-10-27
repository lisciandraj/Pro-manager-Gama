# OptimoRoute Pro → Coco TMS

Date de vérification : 27 octobre 2026. Destination : module TMS existant de Coco ERP, PWA pour GAMA à Quito, 2–5 véhicules, 20–100 livraisons/jour. Référence fonctionnelle : offre Pro. Reconstruction native ; aucune dépendance à un abonnement OptimoRoute.

## Sources publiques

| Source | Éléments observés |
| --- | --- |
| https://optimoroute.com/pricing/ | Pro : 1 000 commandes simultanées, historique, exports, application chauffeur, suivi, ETA, traces, analytique, planification hebdomadaire, preuve, avis client |
| https://optimoroute.com/features/ | Planning, contraintes, modification manuelle, capacités, suivi, UX conducteur |
| https://help.optimoroute.com/hc/en-us/articles/27646167270676-View-and-understand-order-detail-fields | Priorités, durée, trois créneaux, compétences, caractéristiques véhicule, affectation, dates autorisées |
| https://optimoroute.com/faq/ | Jusqu’à cinq semaines, équilibrage par arrêts ou temps, disponibilités et dépôts |
| https://optimoroute.com/workload-balancing/ | Objectifs d’équilibrage et utilisation de la flotte |
| https://optimoroute.com/new-live-tracking-tools-to-improve-performance/ | Position récente, avancement et retard |
| https://optimoroute.com/customer-feedback/ | Note et commentaire après service |
| https://optimoroute.com/analytics/ | Comparaison prévision/réalisation |
| https://optimoroute.com/api/ | Modèle public d’intégration des commandes et de planification |
| https://optimoroute.com/terms-of-service-for-drivers/ | Restrictions sur l’utilisation du service pour construire un concurrent ; sources publiques exclusivement, aucun compte du produit utilisé |

Les écrans du produit authentifié n’ont pas été observés. Les éléments ci-dessous décrivent les fonctions documentées, pas une validation pixel par pixel ni une égalité des résultats de son algorithme privé.

## Écrans

| ID | Écran Coco | Fonction | États |
| --- | --- | --- | --- |
| S01 | TMS / Planifier | Carte, livraisons et tournées du jour | vide, chargé, attente, erreur, mobile |
| S02 | Planning étendu | Vue semaine, période 1–35 jours, aperçu puis application | aucun candidat, exclusions, conflit, droits refusés |
| S03 | Contraintes | Créneaux, jours, compétences, véhicule et conducteur imposé | lecture, édition, version périmée, entrée invalide |
| S04 | Ressources | Horaires, vitesse relative, compétences et équipements | ressources Flotte, sauvegarde, conflit |
| S05 | Suivi | Positions, fraîcheur GPS, arrêts, traces et ETA | pas de position, ancienne, en direct, terminé |
| S06 | Mi ruta | Navigation, réception, activation/arrêt du GPS | connecté, hors ligne, GPS refusé, session expirée |
| S07 | Suivi client | Statut, ETA et avis après livraison | jeton invalide/expiré, en cours, livré, avis déjà soumis |
| S08 | Analyse / exports | Prévu/réalisé, couverture GPS, satisfaction, CSV/GPX | aucune donnée, période invalide, téléchargement |

## Parcours

F01 Commande confirmée → préparation/scan → livraison TMS → contraintes → planning → chargement → départ → réception → facturation/retour existants. Ne jamais créer de deuxième registre de livraison.

F02 Planning étendu → dates et objectif → aperçu → application avec empreinte et clé de requête → calendrier et exclusions. Rejeu identique ; concurrence refusée ; tournées parties/manuelles conservées.

F03 Ressource Flotte → qualifications/horaires → livraison exigeant ces capacités → planifier → motif visible si aucune ressource ne convient.

F04 Conducteur authentifié → démarrer GPS → positions durant la tournée → dispatch voit fraîcheur et traces → arrêter GPS ou fermer session. Pas de collecte invisible ni de GPS fictif.

F05 Lien client aléatoire → statut et ETA → réception effectuée → note/commentaire → avis unique. Aucun accès aux autres clients, photos ou traces du chauffeur.

F06 Période → analyse prévisions/réalisation → export CSV ou GPX autorisé. Pas d’estimation présentée comme une mesure routière.

## Composants et modèle

Réutiliser ArcUI.dialog/table/button, panneaux Coco, carte locale, quatre étapes métier, CocoTmsExecution et l’outbox hors ligne. Modèles supplémentaires : règle livraison (1:1), profil conducteur (1:1 Flotte), profil véhicule (1:1 Flotte), paramètres planning, position GPS (N:1 tournée), avis (1:1 livraison), photographie de planning. Toutes les données additionnelles sont privées, commandées par RPC avec droits TMS/MFA existants.

## Limites et taille

8 écrans, 6 parcours. Complexité L. Les trois points difficiles : optimisation sous contraintes, concurrence intermodules, GPS mobile hors premier plan. Le moteur propriétaire, ses cartes et ses actifs ne sont pas repris. La PWA ne peut pas garantir la collecte GPS écran éteint comme une application native. Les notifications SMS automatiques nécessitent un fournisseur configuré ; aucun envoi simulé. Les fonctions de l’offre Custom (longue distance avec nuitées, matières dangereuses, dépôts dynamiques) ne font pas partie du périmètre Pro.


## Complément public : capacités et lieux

Les capacités configurables et les lieux de départ/fin indépendants sont décrits dans les références publiques du fournisseur : [paramètres des conducteurs et véhicules](https://optimoroute.com/driver-and-vehicle/) et [référence API publique](https://optimoroute.com/api/). Leur comportement a été réimplémenté dans les règles natives Coco, sans appel aux services du fournisseur. Les rechargements intermédiaires automatiques ne font pas partie de cette extension.
