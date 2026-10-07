# Photographies de papeterie et d’entretien GAMA — 7 octobre 2026

## Résultat

30 photographies supplémentaires ont été ajoutées aux fiches partagées par Coco et le site public : trois calculatrices Casio, deux marqueurs Edding, deux agrafeuses KW-trio, treize articles Enkador et dix produits d’entretien ou d’hygiène. Le catalogue compte désormais 429 produits actifs illustrés sur 1785. Il reste 1356 fiches sans photographie vérifiée, dont 40 services sans objet physique.

Les photographies proviennent de pages publiques de Casio, Edding, Enkador, Kimberly-Clark Professional, Kywi, Rogers Stationery et Megapopular. Chaque image retenue a été inspectée visuellement. Aucun visuel produit n’a été généré par IA. Les images Ippo avec filigrane et le visuel « coming soon » du marqueur Snowman 500 ont été écartés ; aucun filigrane n’a été supprimé.

## Correspondances et provenance

Les modèles Casio, Edding et KW-trio sont identifiés par leur référence fabricant. Les articles Enkador sont rapprochés par le code produit présent dans le nom GAMA et par le type de produit, en distinguant les ensembles des recharges. Les anciennes dimensions des libellés GAMA ne sont pas toutes confirmées par le catalogue actuel du fabricant. Lorsque la page détaillée n’est pas publiquement consultable, la provenance renvoie à la liste publique présentant la photo et l’article.

Pour les références d’entretien ne comportant pas de numéro fabricant, la correspondance porte sur la marque, la gamme et la présentation indiquées dans le catalogue. Une couleur ou un parfum visible sur la photo ne constitue pas une nouvelle garantie de variante lorsque la fiche GAMA ne la spécifie pas. Les photos des rouleaux Kleenex 130 m et Scott 305 m proviennent des pages fabricant correspondant à ces présentations.

Le [registre de provenance](data/storefront-product-photo-sources-2026-10-07.json) contient désormais 408 ajouts cumulés, avec page source, URL de l’image, méthode de correspondance, dimensions et empreinte SHA-256. Les 21 photos déjà présentes avant la refonte sont conservées. L’accessibilité publique des photos de tiers ne constitue pas une affirmation de licence libre, Creative Commons ou de domaine public.

Les 30 fichiers WebP représentent 736 006 octets, avec un côté maximal de 720 pixels, sans agrandissement. Ils sont stockés dans `products.photo_data`, partagé par Coco et le site. Aucun lien d’image distant n’est nécessaire à leur affichage.

## Intégrité et affichage

L’import en 14 petits lots exigeait un produit actif, le même identifiant, nom et référence, ainsi qu’un champ photo vide. Les 30 ajouts ont réussi, sans remplacer de photo existante. Le déclencheur existant a synchronisé `has_photo` ; aucune incohérence n’a été détectée.

L’empreinte des lignes produits ordonnées, en excluant uniquement `photo_data`, `has_photo` et `updated_at`, est identique avant et après : `86b0a2d3dfaaf181fb309c33b7739b2a`. Les prix, stocks, noms, références et autres champs sont donc inchangés pendant cet import.

Les [contrôles de production](data/storefront-stationery-photo-verification-2026-10-07.json) confirment les 30 empreintes SHA-256 via l’API publique. La calculatrice Casio AX-120B, référence CAL005, a été contrôlée à 320, 390 et 1440 pixels : même photo dans le catalogue et la fiche, libellé en minuscules, aucun débordement horizontal en grille, en liste ou dans la fenêtre produit, et aucune erreur JavaScript. Les captures téléphone ont été inspectées visuellement. Aucun devis n’a été envoyé.

La [liste restante](data/storefront-missing-photos-2026-10-07.csv) a été réduite à 1356 fiches, en conservant les motifs de non-correspondance déjà identifiés. Elle ne signifie pas que toutes les recherches sont épuisées. Les photos sont diffusées dynamiquement depuis la base commune, sans redéploiement nécessaire du site.

## Lot suivant

Un [quatrième lot de 51 photographies](storefront-expanded-photos-2026-10-07.md) complète ces résultats historiques. Le registre de provenance et la liste des photos manquantes reflètent désormais le cumul des quatre lots.
