# Photographies supplémentaires GAMA — 7 octobre 2026

## Résultat

51 nouvelles photographies ont été intégrées dans la base commune à Coco et au site public : 21 consommables d’impression, 15 produits de cafétéria, 12 disques de nettoyage 3M et 3 produits Activox, Kufer Q ou Hepalive. Le catalogue compte 480 produits actifs illustrés sur 1785. Il reste 1305 fiches sans photographie vérifiée, dont 40 services sans objet physique.

Ce quatrième lot prolonge les 236, 142 et 30 ajouts précédents. Les 21 photographies présentes avant la refonte sont conservées. Le [registre de provenance](data/storefront-product-photo-sources-2026-10-07.json) contient les 459 ajouts cumulés ; la [liste restante](data/storefront-missing-photos-2026-10-07.csv) conserve les motifs de non-correspondance déjà identifiés. Cette liste ne signifie pas que toutes les recherches sont épuisées.

## Sélection et limites des correspondances

Les photos proviennent des pages publiques de 3M, HP, Nescafé Dolce Gusto, CDRmarket, Toners USA, Pharmacys, AKÍ et Supermaxi. Chaque photo retenue a été inspectée visuellement avant l’import. Aucun visuel produit n’a été généré par IA et aucun filigrane n’a été supprimé. L’accessibilité publique d’une photo ne constitue pas une affirmation de licence libre, Creative Commons ou de domaine public.

Les consommables sont rapprochés par référence fabricant, type et couleur. Les fiches indiquant plusieurs références incompatibles ou confondant un tambour avec un toner ont été écartées. La photo HP 111S correspond au modèle Samsung MLT-D111S indiqué par la page fabricant, avec son emballage HP actuel. La référence Xerox 108R00604 identifie une encre solide ; le libellé historique « toner » dans GAMA n’a pas été réécrit.

Les photos 3M identifient la gamme et la couleur des disques : blanc 4100, rouge 5100 et noir 7200. La photo générique de la gamme n’établit pas à elle seule le diamètre ou le nombre de disques dans la boîte. Les dimensions et conditionnements du catalogue restent inchangés. Pour les capsules Dolce Gusto, la variété est vérifiée ; aucune quantité n’est ajoutée au libellé GAMA lorsqu’il ne la précise pas. Les cafés, édulcorants et Coffee Mate avec poids ou nombre de sachets explicites ont été vérifiés sur leur emballage.

La recherche Pharmacys a trouvé de nombreux visuels de remplacement : illustration « imagen restringida », gélules génériques ou image absente. Ils n’ont pas été importés. Les photographies Alka-Seltzer Boost, Voltaren portant une concentration différente et Nescafé Gold avec un logo distributeur ont aussi été écartées. Les [42 exclusions de cette revue visuelle](data/storefront-expanded-photo-rejections-2026-10-07.json) indiquent leur provenance et leur motif. Les variantes non identifiées ne sont pas remplacées par une marque ou un dosage supposés.

## Import et vérification

Les 51 WebP représentent 1 346 744 octets, avec un côté maximal de 720 pixels et sans agrandissement. Ils sont intégrés à `products.photo_data` ; leur affichage ne dépend pas de liens d’images distants. L’import en 25 petits lots a exigé le même identifiant, nom et référence, un produit actif et un champ photo vide. Les 51 ajouts ont réussi sans écraser de photographie existante ; `has_photo` reste cohérent.

L’empreinte de toutes les lignes produits ordonnées, en excluant seulement `photo_data`, `has_photo` et `updated_at`, est identique avant et après : `86b0a2d3dfaaf181fb309c33b7739b2a`. Prix, stocks, noms, références et autres champs sont donc inchangés pendant cet import.

Les [contrôles de production](data/storefront-expanded-photo-verification-2026-10-07.json) valident les 51 empreintes SHA-256 via l’API publique. La référence CARE0016 a été contrôlée à 320, 390 et 1440 pixels : photo identique dans le catalogue et la fiche, première lettre du produit en majuscule, aucun débordement horizontal dans la grille, la liste ou la fiche, et aucune erreur JavaScript. Les captures téléphone ont été inspectées. Aucun devis n’a été envoyé. Les photos sont diffusées dynamiquement depuis la base partagée ; aucun redéploiement du site n’est nécessaire pour ce lot.
