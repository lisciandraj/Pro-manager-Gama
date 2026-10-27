# TMS : flux quotidien, tournées et preuves de livraison

## Planning étendu et suivi

**Planification et suivi** ouvre quatre vues dans le TMS : calendrier, ressources, suivi, analyse et exports. Les commandes, colis, réceptions, retours et paiements restent ceux du parcours ci-dessous.

Le calendrier accepte une période de 1 à 35 jours à partir d’aujourd’hui, jusqu’à 1 000 livraisons liées à des commandes. **Aperçu** annonce la période et le volume ; **Appliquer le planning** vérifie son empreinte et refuse les changements intervenus entre-temps. Les dates flexibles et jours autorisés concernent uniquement les livraisons non affectées et non parties. Les livraisons qui ne tiennent pas le premier jour peuvent passer au prochain jour autorisé, dans la période. Une réexécution de la même requête conserve son résultat et ne reproduit aucun mouvement de stock. Les tournées protégées par un départ, un horaire ou une modification manuelle ne sont pas réécrites.

**Contraintes** propose jusqu’à trois créneaux en heure de Quito, durée de service, quatre priorités, jours et dates autorisés, conducteur imposé, compétences et équipements nécessaires. **Ressources** complète Flotte avec les qualifications, horaires individuels et un facteur de vitesse de 0,5 à 1,5. Les versions empêchent d’écraser une modification concurrente. Les qualifications et créneaux sont aussi vérifiés lors de la saisie de l’horaire et du contrôle de départ. Les modes par nombre d’arrêts ou temps estimé sont des heuristiques, sans garantie de retrouver les tournées d’un moteur tiers.

Dans **Ma tournée**, le chauffeur affecté à une tournée partie peut activer **Partager le GPS**. Le navigateur demande l’autorisation de localisation. La position, sa précision, l’heure appareil et l’heure serveur sont conservées ; le dispatch voit la fraîcheur, les arrêts et les 2 000 dernières positions de la tournée. La collecte s’arrête à la fermeture/au masquage de la page ou au changement de compte. Elle ne fonctionne pas de manière garantie écran éteint. Une position de moins de cinq minutes et de précision inférieure ou égale à 200 m permet une ETA recalculée, toujours estimée, sans réécrire la prévision conservée pour l’analyse. La collecte est limitée côté serveur à une mesure par dix secondes au maximum ; l’interface envoie environ toutes les trente secondes.

Le lien client existant permet, après livraison complète, de donner une note de 1 à 5 et un commentaire. Il n’expose ni les coordonnées des autres livraisons ni la trace GPS du chauffeur. Un jeton expiré est refusé ; un avis déjà déposé ne peut pas être remplacé par un second appel. Les avis entrent dans l’analyse et l’historique avec une référence à la livraison.

**Analyse et exports** présente OTIF, livraisons, satisfaction, prévisions de distance/durée, couverture GPS et écart d’arrivée. Le CSV protège les cellules contre l’exécution de formules ; le GPX regroupe les points GPS des arrêts par tournée pour les appareils compatibles. L’export conserve les permissions TMS existantes, est limité à 10 000 lignes et demande de réduire la période au-delà. Aucun kilométrage réel complet n’est déduit d’une trace partielle.

La comparaison aux fonctions documentées d’OptimoRoute Pro et ses limites figurent dans [le dossier Replica](../../replica/optimoroute-pro/recon.md). Les notifications restent dans le parcours manuel existant ; aucun abonnement SMS, compte externe ni application native n’est activé par cette extension. Le tracé routier facultatif de la carte quotidienne est décrit plus bas. La migration `tms_pro_planning_tracking` précède la publication des nouveaux actifs.

Dans **Préparer**, chaque scan conserve son mode (confirmation de quantité, unité ou conditionnement). Lorsque toutes les quantités prévues de la préparation ont été enregistrées, Coco ferme les colis et les transmet automatiquement au TMS, sans boutons **Fermer le colis / Cerrar preparación** ni **Envoyer au TMS**. Les colis créés manuellement sont conservés ; seules les quantités encore non emballées sont ajoutées à un nouveau colis. Les poids restent calculés depuis les fiches produits. La date de planification reprend la dernière date convenue des lignes préparées, au plus tôt aujourd’hui dans le fuseau de l’ERP.

La RPC `gama_preparation_dispatch` regroupe emballage, clôture et création de la livraison dans une transaction, avec les mêmes contrôles métier et droits TMS/MFA que les actions existantes. Un colis incomplet ne peut pas être transmis. Une livraison partielle exige toujours son motif ; la politique « attendre la livraison complète » et la quantité convenue du prochain envoi restent bloquantes. Une erreur annule l’ensemble de la transmission, sans annuler les scans déjà validés. La reprise conserve la clé de requête ; une préparation déjà transmise renvoie sa livraison existante, même après une réouverture de l’écran. Le contrôle de chargement et l’autorisation de départ restent distincts de cette transmission au TMS.

Le module ouvre une vue **Hoy** avec les étapes **Preparar → Planificar → Cargar → Entregar** et leurs compteurs. Le responsable sélectionne l’étape à traiter. Le premier affichage attend uniquement les ressources, tournées, livraisons, réglages et compteurs du jour. RH et clients se chargent ensuite avec un cache de 60 secondes propre à la session. Les archives de preuves attendent l’étape Entregar. Une lecture du jour de moins de 30 secondes est réutilisée avant la planification ; la relecture après cette mutation est conservée. Préparer compte les commandes confirmées avec des marchandises restant à expédier ; les commandes n’ont pas de date de préparation, ce compteur est global. Les autres compteurs utilisent la date de planification choisie. Le bandeau indique les incidents. Les anciens accès préparation, chargement et preuve restent compatibles. L’historique TMS est remplacé par **Auditoría → Transferencias**, qui lit aussi les événements déjà enregistrés, avec personne, date et référence ERP.

Les livraisons proviennent du parcours commande/préparation existant. Une insertion sans lien à `sales_deliveries` est refusée en fin de transaction ; les anciennes livraisons restent consultables. La date peut être choisie jusqu’à un an dans le futur. L’actualisation explicite et le repli sans délégation déclenchent `gama_tms_plan_day(date)` ; la règle serveur activée traite les événements en arrière-plan. Les autres dates ne sont pas avancées automatiquement.

Le serveur conserve les règles de session/MFA, les droits TMS, les ressources Flotte/RH disponibles et les capacités de poids/volume. Un poids maximal absent bloque le véhicule. Le planner préserve les tournées parties, en chargement, terminées, historiques, mixtes, avec horaires routiers ou ajustées manuellement. Les arrêts se réordonnent par glisser-déposer ou boutons monter/descendre ; un sélecteur permet de changer de tournée sur téléphone. La mutation vérifie les versions des deux tournées, leur date, le départ et la capacité ; une mise à jour concurrente demande une actualisation.

Les coordonnées sont réutilisées depuis la fiche client lorsque son adresse correspond. Une correction TMS enregistre aussi la position du client seulement si l’adresse correspond. Un changement d’adresse invalide la position ancienne. Les champs latitude/longitude sont disponibles dans Contactos. **Carte des livraisons du jour** affiche une carte locale multipoints, enrichie avec plus de 64 000 segments du réseau municipal de Quito, ses rues et leurs noms. L’actif détaillé se charge sur demande depuis Coco, sans clé ni API cartographique. Le cadrage initial inclut toutes les livraisons géolocalisées et le dépôt, même hors de Quito. Sans GPS, la vue reste centrée sur Quito (−0,1807, −78,4678). Les boutons +/−, le glissement, le pincement tactile et les flèches du clavier permettent le déplacement, jusqu’au détail des rues ; une échelle indique les distances. Le filtre limite les points à une tournée ; sélectionner un client centre la vue sans supprimer les autres marqueurs. Les points proches sont décalés visuellement avec un trait vers leur position exacte, à l’intérieur du cadre disponible en vue générale, et le cadrage s’adapte au redimensionnement sur téléphone. Les traits de tournée en pointillés indiquent l’ordre ; l’option routière décrite ci-dessous peut ajouter un tracé suivant les rues. Le fond national reste Natural Earth et le détail municipal couvre Quito et ses vallées ; aucune position fictive n’est créée. Voir [provenance et couverture du fond](../tms-map-data.md).

**Mi ruta** reconnaît un conducteur lié à son compte, même sur ordinateur. **Descargar para trabajar sin conexión** prépare la route, les lignes et les fichiers nécessaires à `tms-driver.html`. Cette page se rouvre hors ligne pendant 48 heures après téléchargement. Les commandes sont stockées avant envoi dans l’IndexedDB historique `architect-proof-outbox` (version 2, migration additive). Elles gardent l’acteur, la clé idempotente, l’heure, les quantités et les preuves. Un échec bloque seulement les commandes suivantes de la même livraison. Une reconnexion exige les droits courants du serveur. Déconnexion explicite ou changement de compte masque la copie locale sans supprimer les preuves non synchronisées. Le mode hors ligne requiert une première préparation en ligne et un navigateur autorisant service worker et stockage local.

**Registrar recepción** permet de répartir chaque solde entre unités acceptées, refusées, manquantes et reportées. Leur somme doit correspondre exactement au solde. Toute quantité acceptée demande nom et signature ; une réception non complète demande un motif ; des manquants demandent une photo. Les quantités refusées créent le retour existant et n’augmentent pas le stock avant réception et inspection. La facturation après signature utilise uniquement les unités acceptées. Chaque essai conserve ses propres lignes, acteur, heures et preuves, sans écraser les essais antérieurs. Le média est conservé dans un schéma privé de la base, avec une projection compatible dans la preuve historique ; le déplacement des anciens médias vers Storage n’est pas effectué par cette version.

**Ventana y carga** enregistre une fenêtre structurée et la durée de service, ainsi qu’une mesure justifiée du poids/volume quand les fiches produit sont incomplètes. La promesse initiale reste immuable pour le KPI. La disponibilité Flotte/RH est évaluée à la date planifiée. Poids et volume inconnus excluent la livraison ou le véhicule de la planification. Le regroupement tient compte des fenêtres sur une estimation de déplacement (distance × 1,3 à 25 km/h, pas une ETA GPS). **Horario** permet de saisir les temps et kilomètres vérifiés ; les dépassements de fenêtre demandent une justification. La sortie contrôle à nouveau disponibilité, capacités et présence d’un horaire pour les fenêtres structurées.

Les profils TMS sont **Despachador**, **Conductor** et **Gestor**, configurables par l’administrateur dans **Roles TMS**, à l’intérieur des accès ERP existants. Sans réglage spécifique, un compte actif lié à un conducteur est restreint à ses livraisons ; les autres utilisateurs autorisés du magasin gardent le dispatch. Les preuves, événements et incidents ne s’écrivent plus directement depuis le navigateur. Les commandes contrôlent la version de la livraison et les droits au moment de synchroniser.

**Manifiesto** télécharge un PDF des arrêts et marchandises avec le générateur local partagé (sans ouvrir une fenêtre d’impression dans la PWA) ; ce document opérationnel ne remplace pas la guía SRI. **Cierre de jornada** montre les soldes, retours ouverts et facturations à revoir. Une livraison partielle ne peut être soldée qu’après résolution des quantités et retours, confirmation de revue de facturation et motif. Son état partiel reste conservé. Une tournée se ferme quand ses livraisons sont livrées, annulées ou résolues.

**Gestionar entrega** propose :

- Préparer un SMS ou WhatsApp avec heure estimée et lien de suivi. Le conducteur confirme l’envoi dans l’application de messagerie ; aucun envoi automatique ni statut « envoyé » n’est simulé. Le serveur enregistre l’ETA et l’événement Aviso preparado. Le lien est un jeton aléatoire valable 30 jours, consultable sans compte : il expose seulement référence, date, état et heures, sans client, adresse, téléphone, photo ou GPS.
- Enregistrer client absent, refus ou adresse incorrecte, puis reprogrammer pour demain en un clic. Le départ original et les mouvements de stock sont conservés puisque les marchandises restent sur le véhicule. La tournée active apparaît aussi à la nouvelle date du prochain essai ; une nouvelle préparation n’est pas créée artificiellement.
- Sélectionner les cartons refusés et créer un retour lié à l’expédition. Les quantités proviennent des lignes de colis et de leur emplacement de prélèvement. Un carton ne peut être retourné deux fois. Le stock ne remonte qu’après réception et inspection dans Devoluciones.
- Saisir espèces ou virement sur une facture du même pedido. Le montant ne dépasse pas son solde ; une caisse ou banque active et compatible avec la devise est obligatoire. La commande est idempotente et crée le paiement standard avec ses écritures existantes. Le serveur requiert les permissions de paiement et le compte du conducteur assigné, ou l’administrateur.

Les coûts de nouvelles tournées conservent le coût/km calculé dans Flota sur la fenêtre de pleins de carburant. Le carburant estimé est km × coût/km ; les composantes supplémentaires vérifiées sont saisissables dans les options de tournée. La répartition par livraison reste uniforme entre arrêts. Un coût absent est affiché comme inconnu. Les indicateurs présentent l’OTIF sur les livraisons avec promesse initiale (livrées intégralement avant la fin de cette fenêtre), sa couverture et les livraisons partielles, ainsi que les livraisons à l’heure parmi celles ayant une ETA, incidents par conducteur, kilomètres et coût estimé par jour ; le parcours routier vérifié est utilisé lorsqu’il existe. Ce calcul n’invente ni charges de personnel ni péages.

Les preuves sont dans un seul tableau triable par date, client/fournisseur, référence et état, avec consultation et téléchargement par ligne. Le fournisseur est celui du document lié lorsqu’il existe ; une livraison client ne reçoit pas un fournisseur fictif. Photos et signatures sont chargées uniquement à la consultation ou au téléchargement. Le PDF et les noms de fichiers utilisent la référence ERP du document, sans UUID de stockage.

La preuve conserve position GPS, précision et heure de l’appareil lorsque la permission est accordée, ainsi que l’heure de réception serveur. Permission refusée ou position indisponible n’engendre pas de coordonnées fictives. La signature pour les quantités acceptées et le contrôle de départ restent obligatoires ; la file hors ligne conserve ces métadonnées. Les preuves historiques ne reçoivent pas une heure de réception inventée.

L’ancien historique local `gama-tms-v1` est conservé sur l’appareil, sans réimporter des livraisons non liées à une commande. Les migrations ne suppriment aucun historique de production.

Le bouton **Coste de entrega por cliente** dans les indicateurs ouvre le détail du mois ou de la période sélectionnée (366 jours au maximum). Les arrêts distincts de chaque tournée partagent son montant arrondi au centime ; les montants des clients retombent exactement sur le total connu. Un client avec plusieurs arrêts reçoit la somme de ses parts. Le tableau regroupe client, livraisons, tournées, km, coût connu et arrêts sans tarif ou avec km estimés. La recherche précède la pagination serveur (30 lignes), avec les mêmes droits TMS/MFA que les indicateurs. Un arrêt historique sans client reste identifié comme inconnu ; les tournées sans arrêt restent signalées séparément. Il s’agit d’une attribution estimée des coûts de tournée, pas d’un règlement de fret.

## Navigation Waze

Depuis le 5 octobre 2026, chaque arrêt et le prochain arrêt de tournée ouvrent Waze par lien HTTPS, à partir du GPS ou de l’adresse. OpenRouteService n’est plus appelé. Coco conserve les distances estimées et ses arrêts ; les temps et kilomètres vérifiés dans Waze se saisissent dans le planning et restent contrôlés avec les fenêtres de livraison. Voir [automatisations et navigation](../automation.md).

La carte des livraisons du jour affiche les commandes de zoom et les points sans les trois textes d’aide « Données locales », « Aucune livraison géolocalisée » et « Tous les points sont affichés ». La provenance du fond reste documentée dans le guide du fond de carte.

## Simplification du 14 octobre 2026

Les douze actions de l’audit sont couvertes par les parcours suivants :

| Action | Comportement livré |
| --- | --- |
| A1 · Horaires | Un seul éditeur, heure de Quito, départ/source/motif et trajets préremplis. Révision concurrente refusée. Un changement d’ordre, GPS, créneau ou service marque le planning à revoir ; seuls les trajets dont les deux extrémités restent identiques sont réutilisés. |
| A2 · Réception | « Livraison complète » accepte les soldes sans afficher quatre champs par produit. « Livraison partielle / incident » déplie les quantités. Nom, signature, motif, photo de manque et somme des quantités restent contrôlés au serveur. |
| A3 · Départ | « Prêt à partir » vérifie conducteur/véhicule, capacités, chargement, GPS, horaires et politique de document SRI. Une seule transaction valide tous les départs par les commandes existantes. Rejeu idempotent, versions des colis et absence de nouveau mouvement de stock. |
| A4 · Navigation | Quatre étapes conservées, options/documents regroupés par tournée, rôles dans Configuration, prochaine livraison mise en avant. Les conducteurs utilisent leur écran limité aux affectations serveur. Nouveaux écrans en espagnol, français et anglais. |
| A5 · Automatisation | La règle existante `tms_planning` reste l’unique ordonnanceur. Configuration affiche état, exécutant, échéance de délégation, dernière exécution et erreur. Renouvellement explicite limité à 90 jours. L’écran vérifie l’état toutes les trois minutes lorsqu’il est visible ; une actualisation explicite reste possible. |
| A6 · Planification | Début/fin de journée, pause, maximum d’arrêts et retour au dépôt. Modèles de clients habituels par conducteur/jours de semaine. Temps vérifiés réutilisés pour les mêmes coordonnées pendant 180 jours ; repli estimé sans appel externe. Les modèles sont des préférences, les contraintes restent prioritaires. |
| A7 · Blocages | Liste des GPS, mesures de charge, ressources et contraintes restant à corriger, avec accès au bon écran. Les données manquantes ne sont jamais inventées. |
| A8 · Hors connexion | `driver-ui.js` est partagé entre ERP et `tms-driver.html`. Préparation automatique des actifs, manifeste et PDF SRI déjà autorisé quand disponible. Compte, ancienneté, file locale et documents indisponibles sont affichés. Les opérations financières nécessitent une connexion. Durée 48 h, plafond 100 captures inchangés. |
| A9 · Historique | « Tout l’historique » recherche côté serveur par période, client/référence et état, par pages de 25, y compris au-delà des 200 anciennes preuves et pour les livraisons partielles. Tous les essais restent consultables, médias chargés à la demande. |
| A10 · Lectures | La vue courante charge la date choisie et ses tournées. Les autres dates sont une liste serveur paginée. La liste de preuves récentes est limitée et annoncée à 50 ; son PDF décrit cette sélection. |
| A11 · Coûts | L’ancien montant est nommé « carburant estimé ». Temps conducteur/taux horaire, péages et véhicule peuvent être renseignés avec justificatif. Vide signifie inconnu ; zéro doit être vérifié. Répartition égale et conservation des centimes, couverture affichée sur quatre composantes. |
| A12 · Clôture | Une liste regroupe file de preuves locale, retours/inspection, quantités/facturation, encaissements, remise d’espèces et documents SRI. Une remise saisie conserve le comptage, l’auteur, la note et la photographie des paiements ; écart ou nouveaux encaissements demandent une nouvelle revue. Elle ne crée aucune écriture ni autorisation fiscale. |

`gama_tms_dispatch` expose les contrôles et listes avec façade invocateur et implémentation privée, droits TMS/MFA et rôles existants. Les réglages, modèles, trajets vérifiés, coûts et remises sont privés. La migration n’active pas de délégation pour un utilisateur arbitraire : la règle se configure pour un administrateur identifié et autorisé.

Les fichiers de nouvelles preuves utilisent le bucket privé `tms-attempt-proofs`. La fonction Edge `tms-proof-files` lit d’abord la preuve au travers du JWT de l’appelant et des contrôles TMS, copie uniquement les octets acceptés, relit l’objet et vérifie SHA-256 avant d’enregistrer sa référence immuable. Aucun upload, écrasement ou effacement direct n’est ouvert au navigateur. Les copies historiques restent disponibles : une indisponibilité de stockage ne bloque pas la confirmation ni ne supprime une capture. Déployer la migration puis cette fonction avant les nouveaux actifs. Aucune reprise massive ni purge d’archives n’est effectuée.

Les tests de base isolée couvrent contraintes, horaires, versions, départ groupé et annulation atomique, rejeu sans stock supplémentaire, coûts et plus de 200 preuves. Les tests d’interface couvrent réouverture d’horaire, réception simplifiée, départ, recherche et mobile ; le parcours hors connexion conserve ses tests de reprise et de changement de compte.


## Carte quotidienne et actualisation automatique

La carte se rafraîchit toutes les 15 secondes pendant que Planifier est visible,
avec reprise immédiate au retour de connexion. Les événements Realtime des tables
TMS déclenchent aussi une lecture regroupée ; le sondage fonctionne même sans
publication Realtime. Les lectures passent par les droits existants. Le filtre de
tournée, le centrage et un zoom/déplacement manuel sont conservés. Les changements
métier actualisent également les listes, sans interrompre un formulaire ouvert.
Les abonnements sont retirés à la sortie et les données sont effacées à la
déconnexion. Les tournées et les livraisons restent filtrées selon la date choisie
(en heure de l’entreprise, Quito par défaut). Aucun traitement du suivi ne relance
le planner ni n’écrit une position ou une livraison.

Les véhicules apparaissent avec les positions explicitement partagées par les
chauffeurs, reçues via `gama_tms_pro('live')`. Une position de plus de cinq minutes
ou une lecture GPS en erreur retire le marqueur du véhicule ; les livraisons
restent consultables. La dernière actualisation et une perte de connexion sont
visibles. Sans livraison, Quito reste affiché avec un état vide explicite. Une
erreur de rendu propose Réessayer au lieu de laisser une zone vide. Les dimensions
SVG explicites stabilisent le rendu dans les dispositions mobiles.

Les couleurs et numéros reprennent l’ordre optimisé du planner Coco ; le départ
et le retour au dépôt sont inclus selon la configuration. Les pointillés indiquent
un ordre estimé, sans prétendre suivre les rues. **Afficher les trajets routiers**
active explicitement un calcul OSRM opéré par FOSSGIS, sans clé payante : seuls les
couples longitude/latitude des arrêts sont transmis, jamais les noms, références,
identifiants ou positions des chauffeurs. Le choix est limité à la session et
réinitialisé à la déconnexion. Les traits pleins suivent la géométrie routière
dans le même ordre, sans modifier les affectations ni les horaires validés. Les
retours et changements de coordonnées invalident le tracé en cours. Une panne du
service laisse les arrêts et l’ordre indicatif disponibles.

Ce calcul utilise un profil voiture, sans trafic en direct, restrictions de
camions ni garantie de disponibilité. Le planner reste une heuristique respectant
ses contraintes existantes, pas une optimisation mondiale des temps routiers.
Waze reste disponible pour la navigation. Le client applique un maximum d’une
requête par 1,1 seconde, un cache mémoire de 15 minutes (30 trajets), une échéance
réseau de 12 secondes et des lots de 90 points. Les attributions OpenStreetMap,
OSRM/FOSSGIS et le lien de correction sont affichés lorsque l’option est active.
La CSP de la seule entrée ERP autorise précisément le chemin de cette API.

Contrôles : `tests/tms-module.spec.js` couvre l’état vide en français sur téléphone,
les mises à jour sans perte de vue, les numéros selon le planning, le suivi GPS,
l’arrêt des lectures, le consentement routier et le repli en cas de panne.
