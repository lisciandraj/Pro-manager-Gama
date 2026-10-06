# Fond de carte détaillé et local TMS

## Rues de Quito

Depuis le 6 octobre 2026, la carte ajoute le réseau municipal **Vialidad, PUGS**, disponible sur [GeoQuito](https://geoquito.quito.gob.ec/server/rest/services/web_image_dmdu/ap030_via_l/MapServer/0). L’extraction complète contient 64 173 entités, préparées en 64 168 lignes non dégénérées, avec les rues, avenues et noms du district de Quito et de ses vallées. Les sources municipales mentionnent notamment IGM, EPMMOP, PUGS, des relevés de terrain et des mises à jour urbanistiques ; il ne s’agit pas d’un relevé en temps réel ni d’un moteur de navigation. La municipalité décrit l’accès et l’utilisation de cette information comme [libres, gratuits et sans conditionnement](https://quitoinforma.quito.gob.ec/2022/06/08/una-plataforma-digital-ayudara-a-reducir-el-trafico-de-tierras-y-asentamientos-informales/).

La source canonique `src/features/transport/quito-map-data.js` est un instantané extrait le 6 octobre 2026. Les lignes sont simplifiées à environ 2 mètres puis quantifiées à 0,00001 degré ; les noms et cinq classes de voies sont conservés. La géométrie est compactée par deltas entiers et varints, pas inventée. L’actif représente environ 1,30 Mo (0,81 Mo gzip), se télécharge depuis Coco seulement lorsque la carte affiche Quito au zoom détaillé et se partage entre les ouvertures. Il n’est pas chargé au démarrage général de l’ERP. Les rues visibles sont sélectionnées par un index spatial, regroupées par classe et les noms apparaissent au zoom utile. Une échelle métrique accompagne la carte.

Préparation et contrôles de l’inventaire : `python3 scripts/import-tms-quito-map.py --download`. L’outil interroge le service public **uniquement lors de la préparation** ; l’application et `npm run build` ne l’appellent jamais. Les réponses intermédiaires restent dans `.build/quito-map-snapshot`. Sans `--download`, le même outil reconstruit l’actif depuis cet instantané local. Il ne lit ni données cadastrales privées ni positions des clients. Aucun nouvel appel Supabase ni changement de schéma n’est nécessaire.

Le détail des rues couvre le district métropolitain (environ −78,937 à −78,203 de longitude, −0,428 à 0,241 de latitude). Les livraisons hors de ce périmètre restent affichées et cadrées ensemble, avec le fond national ci-dessous. Les marqueurs proches se répartissent dans le cadre disponible avec un trait vers leur position GPS réelle. Le bouton de cadrage et le redimensionnement en vue générale incluent tous les points ; zoom ou déplacement manuel restent libres.

## Fond national

Source : [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/), données cartographiques dans le domaine public, jeu 1:10m. Les fichiers GeoJSON sources sont `ne_10m_admin_0_countries`, `ne_10m_roads` et `ne_10m_populated_places` dans le [dépôt officiel des données](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson), extraits le 5 octobre 2026.

`src/features/transport/map-data.js` contient les contours de l’Équateur, du Pérou et de la Colombie, 168 segments routiers intersectant l’Équateur continental et 37 villes équatoriennes. Les coordonnées sont arrondies à 5 décimales ; les lignes sont simplifiées à 0,00035 degré pour limiter le poids. Les données restent livrées avec le logiciel. Elles servent de fond aux vues nationales et sont complétées par le réseau municipal dans Quito. Waze s’ouvre uniquement sur action utilisateur.

Aucune clé, API cartographique, tuile distante, OpenStreetMap ou service Google Maps n’est utilisé par la carte. Les coordonnées des clients restent locales dans cette vue. Le fond n’est pas un document de délimitation territoriale. Les trois textes d’aide retirés de la carte restent absents ; la provenance est documentée ici.
