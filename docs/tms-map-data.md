# Fond de carte local TMS

Source : [Natural Earth](https://www.naturalearthdata.com/about/terms-of-use/), données cartographiques dans le domaine public, jeu 1:10m. Les fichiers GeoJSON sources sont `ne_10m_admin_0_countries`, `ne_10m_roads` et `ne_10m_populated_places` dans le [dépôt officiel des données](https://github.com/nvkelso/natural-earth-vector/tree/master/geojson), extraits le 5 octobre 2026.

`src/features/transport/map-data.js` contient les contours de l’Équateur, du Pérou et de la Colombie, 168 segments routiers intersectant l’Équateur continental et 37 villes équatoriennes. Les coordonnées sont arrondies à 5 décimales ; les lignes sont simplifiées à 0,00035 degré pour limiter le poids. Les données restent livrées avec le logiciel. Elles ne sont pas un réseau de navigation et ne prétendent pas détailler les rues de Quito. Waze s’ouvre uniquement sur action utilisateur.

Aucune clé, API cartographique, tuile distante, OpenStreetMap ou Google Maps n’est utilisé par la carte. Les coordonnées des clients restent locales dans cette vue. Le fond n’est pas un document de délimitation territoriale.
