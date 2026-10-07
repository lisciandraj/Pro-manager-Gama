# Refonte publique GAMA — 7 octobre 2026

## Références graphiques

Dix enseignes reconnues ont servi de références visuelles, sans prétendre établir un classement mondial : [Bureau Vallée](https://www.bureau-vallee.fr/), [Staples](https://www.staples.com/), [Office Depot](https://www.officedepot.com/), [Lyreco](https://shop.lyreco.fr/), [Bruneau](https://www.bruneau.fr/), [Viking](https://www.viking-direct.co.uk/), [Papier](https://www.papier.com/), [MUJI](https://www.muji.com/), [Ryman](https://www.ryman.co.uk/) et [SuperPaco](https://www.superpaco.com/).

Les distributeurs professionnels ont inspiré la recherche permanente, les filtres et la sélection de devis. Papier et MUJI ont inspiré les espaces blancs, la typographie et la sobriété. Les compositions graphiques et les textes de ces enseignes ne sont pas copiés. L’identité GAMA conserve son logo et ses couleurs. Les photographies de produits utilisées sont documentées séparément ci-dessous.

## Livraison

Accueil éditorial, cartes en grille, variante en liste, filtres accessibles, navigation mobile, fiche produit et devis. Les pistes flexibles peuvent se réduire, les mots longs reviennent à la ligne et les champs numériques restent dans leurs cartes. Les photos sont communes à Coco et au site ; les images de catégories générées par IA ne sont plus publiées.

1784 produits actifs et un produit archivé ont eu leurs noms ou marques entièrement en majuscules normalisés. Les valeurs de catégorie, références et codes-barres sont conservés. Dans la fiche Coco, les champs de classification entièrement en majuscules sont présentés en minuscules sans changer leurs valeurs utilisées par les filtres. Le site applique la même normalisation aux futurs libellés. À la demande du propriétaire, une majuscule initiale est maintenant présentée sur les noms de produits et catégories, sur le site, dans le portail B2B et les fiches Coco ; les valeurs de classification stockées restent inchangées.

Un premier lot de 236 photographies réelles du catalogue historique de la même entreprise a été vérifié et ajouté, sans écraser les 21 photos existantes. Un [second lot de 142 photos vérifiées](storefront-photo-enrichment-2026-10-07.md), puis un [troisième lot de 30 photos de papeterie et d’entretien](storefront-stationery-photos-2026-10-07.md), puis un [quatrième lot de 51 photos](storefront-expanded-photos-2026-10-07.md), portent à 480 le nombre de produits actifs illustrés sur 1785. Elles sont compressées en WebP et stockées dans `products.photo_data`. Les [sources et empreintes](data/storefront-product-photo-sources-2026-10-07.json) couvrent les 459 ajouts. 1305 produits actifs restent sans photographie vérifiée, dont 40 services sans objet physique : [liste à compléter](data/storefront-missing-photos-2026-10-07.csv). Les limites de correspondance des variantes et anciennes dimensions sont précisées dans les audits ; une référence ambiguë n’est pas présentée comme un modèle exact.

La sélection mise en avant utilise un cahier, un stylo, une agrafeuse et un clavier réellement publiés, avec leurs photos. Les données commerciales, les prix, les stocks et les documents historiques ne sont pas réécrits par la refonte.

## Informations légales et données personnelles

Les champs raison sociale, RUC et e-mail de confidentialité sont disponibles dans Site public, avec un signalement des valeurs manquantes. Le propriétaire a choisi de les compléter plus tard. Le RUC de onze chiffres présent dans l’ERP n’est pas repris comme un numéro valide de treize chiffres.

Les textes couvrent le fonctionnement d’une demande de devis, les prix et taxes, la confirmation commerciale, livraison/changements/garanties, finalités et données collectées, champs obligatoires et consentement, prestataires et traitements internationaux, conservation et droits, et stockage de session. Ils ne garantissent pas une conformité juridique complète tant que l’identité et les pratiques réelles de l’entreprise ne sont pas renseignées et validées.

Références primaires : [loi équatorienne sur le commerce électronique](https://www.telecomunicaciones.gob.ec/wp-content/uploads/downloads/2012/11/Ley-de-Comercio-Electronico-Firmas-y-Mensajes-de-Datos.pdf), notamment l’information préalable et le consentement ; [consultations 2026 de la SPDP](https://spdp.gob.ec/consultas2026/), notamment le droit à l’information et la conservation limitée aux finalités. Aucun délai de retour ni durée uniforme de conservation n’est inventé.

## Traçabilité

Les migrations ajoutent le schéma des informations légales et sélectionnent les photos de catégories parmi les produits photographiés et publiés, avec les autorisations existantes. Les tables privées et les contrôles de devis, B2B, RLS et prix restent en place. Les [textes et réglages avant modification](data/storefront-before-2026-10-07.json), [texte archivé](data/storefront-archived-text-before-2026-10-07.json) et [mise en avant antérieure](data/storefront-featured-before-2026-10-07.json) sont conservés pour une restauration contrôlée.

Les tests de base restaurent les migrations dans PGlite. Les tests navigateur couvrent Chrome et WebKit, huit largeurs de 320 à 1440 px, navigation, recherche, variantes de catalogue, quantités, devis sans doublon, photos partagées et liens légaux. Aucun test n’envoie de devis ou d’invitation en production.

Un cinquième lot autorisé de [1305 visuels illustratifs](storefront-illustrative-photos-2026-10-07.md) complète désormais toutes les fiches actives : 1785 produits sont illustrés. Les photos génériques sont signalées et leurs sources sont accessibles dans le pied du catalogue.
