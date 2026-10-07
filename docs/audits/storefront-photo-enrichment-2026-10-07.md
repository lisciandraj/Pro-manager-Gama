# Enrichissement des photographies GAMA — 7 octobre 2026

Les nombres ci-dessous décrivent ce lot de 142 photos au moment de son import. Un [lot ultérieur de 30 photos](storefront-stationery-photos-2026-10-07.md) porte le total à 429 produits illustrés et met à jour le registre de provenance et la liste restante partagés.

## Résultat

142 photographies de produits supplémentaires sont disponibles dans les fiches partagées par Coco et le site public. Le catalogue compte désormais 399 produits actifs illustrés sur 1785 : 21 photos préexistantes, 236 ajouts du premier lot et 142 de ce lot. Il reste 1386 fiches sans photo vérifiée, dont 40 services sans objet physique. Ce lot ne complète donc pas l’illustration de tout le catalogue.

Les photos proviennent de pages publiques de HP, Xerox, Epson, Canon, Lexmark, SuperPaco, GM Supplies et du catalogue historique GAMA. Les correspondances s’appuient sur les références fabricant, les codes-barres corroborés par le type de produit ou une correspondance précise avec l’ancien catalogue de l’entreprise. Chaque image retenue a été inspectée visuellement. Aucun visuel produit n’a été généré par IA.

Les fichiers sont compressés en WebP, sans agrandissement, avec un côté maximal de 720 pixels. Pour sept photos, seules les marges blanches extérieures excessives ont été réduites. Les 142 fichiers représentent 4 187 624 octets. Les images sont stockées dans `products.photo_data` ; leur affichage ne dépend pas d’un lien distant vers un autre commerçant.

## Sources et limites

Le [registre de provenance](data/storefront-product-photo-sources-2026-10-07.json) contient les 378 ajouts cumulés, avec URL de la photo, page produit, méthode de correspondance, dimensions, date et empreinte SHA-256. Pour les photos de tiers, leur accessibilité publique ne constitue pas une affirmation de licence libre, Creative Commons ou de domaine public. Les emballages peuvent être ceux du marché de la source ; la référence fabricant doit correspondre.

Les photos Xentair présentant un filigrane ont été écartées. Deux images GM Supplies ont également été rejetées : la page du toner jaune Xerox 106R01319 présentait du magenta, et celle du noir 106R00675 présentait également du magenta. Aucun filigrane n’a été supprimé. Une illustration de boîte d’étiquettes et une icône générique de fabricant ont été exclues du lot de photographies.

Les références ou libellés contradictoires restent à clarifier : notamment HP 60/60XL, Epson S015073 black/couleur et des fiches Xerox confondant toner et tambour. Les fiches regroupant plusieurs références couleur n’ont pas reçu la photo d’une seule variante présentée comme celle du lot entier. La [liste des 1386 fiches restantes](data/storefront-missing-photos-2026-10-07.csv) distingue ces cas connus des produits dont la photo reste simplement à identifier ; elle ne prétend pas que toutes les autres recherches sont épuisées.

## Intégrité et vérification

L’import a été exécuté en 88 petits lots. Chaque modification exigeait un produit actif, le même identifiant, le même nom et la même référence, ainsi qu’un champ photo vide. Les 142 ajouts ont réussi et aucune photo existante n’a été remplacée. Le déclencheur existant a synchronisé `has_photo`, sans nouvelle migration ni changement des autorisations.

L’empreinte MD5 des lignes produits ordonnées, en excluant uniquement `photo_data`, `has_photo` et `updated_at`, est identique avant et après : `86b0a2d3dfaaf181fb309c33b7739b2a`. Les prix, stocks, noms, références et autres champs sont donc inchangés pendant cet import. Aucune incohérence entre `has_photo` et le contenu photo n’a été détectée parmi les produits actifs.

Les [contrôles de production](data/storefront-photo-enrichment-verification-2026-10-07.json) confirment les 142 empreintes SHA-256 via l’API publique. La fiche HP 712 noir 80 ml, référence THPQ551, a été vérifiée à 320, 390 et 1440 pixels : même photographie dans le catalogue et la fiche, nom en minuscules, absence de débordement horizontal en grille, en liste et dans la fenêtre produit, sans erreur JavaScript. Les captures téléphone ont été inspectées visuellement. Aucun devis n’a été envoyé.

Les photos sont servies dynamiquement depuis la base commune. Aucun redéploiement du site n’est nécessaire pour ce lot ; les sources et les éléments de contrôle sont conservés dans Git.
