# TMS : commandes, carte et planification quotidienne

Les livraisons sont créées par le parcours de commande/préparation existant. Le formulaire d’ajout manuel a été supprimé. Le serveur refuse également une insertion TMS sans lien `sales_deliveries` à la fin de la transaction ; les anciennes livraisons restent consultables.

L’onglet Planification affiche les livraisons de la journée de l’entreprise, leur carte et les tournées. Son ouverture, les changements de données et une actualisation toutes les 45 secondes lorsque la page est visible déclenchent `gama_tms_plan_day`. Le bouton Actualiser permet de réessayer un échec ou un géocodage. Les autres dates ne sont jamais avancées automatiquement.

Le traitement serveur est transactionnel et idempotent : verrou par journée, contrôle de session/MFA et des droits TMS administrateur/magasinier, ressources Flotte/RH disponibles, capacités de poids et volume, priorités puis voisin le plus proche. Un poids maximal absent bloque le véhicule ; un volume maximal absent n’impose pas de plafond volumétrique. Une tournée partie, en chargement, terminée ou dotée d’un horaire routier manuel est conservée. Son conducteur et son véhicule ne sont pas affectés à une nouvelle tournée ce jour-là. Les tournées historiques ou mixtes sont conservées.

Les adresses sans coordonnées sont recherchées via Nominatim, séquentiellement avec au moins une seconde entre les appels, au plus quatre livraisons par passage, délai maximal et résultats persistés. Les recherches échouées ne sont pas répétées à chaque passage. Le bouton de correction permet de saisir les coordonnées réelles d’une livraison existante ; il ne crée aucune livraison. L’adresse et les coordonnées du dépôt sont configurables sur cette page.

La carte utilise les tuiles OpenStreetMap, sans SDK supplémentaire, avec sélection de tournée, zoom, ajustement à l’ensemble et arrêts numérotés. Les points sans coordonnées ne sont pas placés artificiellement. Si le fond de carte échoue, les points et tournées restent affichés avec un avertissement. Les adresses nécessaires au géocodage et les tuiles sont demandées à ces services externes.

La proximité utilise des distances à vol d’oiseau : les traits ne représentent pas un trajet routier et les créneaux horaires ne sont pas garantis. Les itinéraires peuvent être ouverts dans Google Maps ; les horaires routiers existants sont préservés. Les dossiers de préparation, contrôle de chargement et preuve de livraison restent accessibles.

L’ancien historique `gama-tms-v1` est conservé sur l’appareil mais n’est plus importé automatiquement sans lien à une commande. Aucune donnée historique de production n’est supprimée par cette migration.
