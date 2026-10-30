# Geex / GAMA — vérification du 30 octobre 2026

La direction approuvée remplace l’apparence ERP par une reconstruction des captures Geex fournies, avec les couleurs GAMA. Les preuves portent sur le code compilé et des fixtures isolées. Aucun fichier Figma ni code Geex n’a été importé ; aucune publication en production n’est attestée ici. Le [contrat ERP](DESIGN.md) et la [fiche de surface](.impeccable/surfaces/coco-erp.md) décrivent le périmètre.

## Contrôles réalisés

- `npm run validate` réussi : 760 tests au total, 758 réussis, 2 ignorés, aucun échec. Ce résultat ne signifie pas que les suites navigateur ont été exécutées localement.
- Les suites navigateur locales ne peuvent pas lancer leur serveur dans cet environnement : refus de socket `EPERM`. Leur exécution Chromium/WebKit est suivie dans GitHub Actions. Un passage Contacts a réussi 66 tests avec une attente périmée de graisse ; un passage d’audit a réussi 143 tests avec une attente périmée de tiroir sur PC. Ces attentes, ainsi que les anciennes attentes de bandeau et de grille, ont été adaptées au contrat courant. La validation finale CI des corrections reste en attente ; la PR 274 reste ouverte.
- Budget de démarrage mesuré : 296 165 octets CSS sur 300 000 ; 14 scripts ; 797 891 octets JavaScript sur 850 000. Aucun plafond n’a été augmenté. Ces poids ne mesurent pas le temps de chargement réseau.
- Poppins régulier, moyen et semi-gras sont livrés localement, pour 28 768 octets WOFF2 au total, avec la licence SIL OFL 1.1 dans `fonts/Poppins-OFL.txt`. La [preuve de chargement](geex-gama-font-evidence.json) indique Poppins chargée ; ses champs réseau ne sont pas un calcul du poids total des fichiers.
- À 320 px après ajustement du palier compact : les 25 tuiles mesurées sont carrées (89,65625 px de côté), aucun titre ne dépasse son carré et le débordement horizontal de page est nul. L’ajustement corrige un dépassement de titre de 1,8 px observé lors de la QA. Voir les [mesures DOM à 320 px](geex-gama-320-evidence.json).
- À 1180 px : sept colonnes, barre latérale de 244 px, début du contenu à 276 px et débordement horizontal nul. Le libellé « Base de connaissances » est complet sur environ deux lignes : 12 px, hauteur 32,375 px, interligne 16,2 px et largeur 92,5625 px. Voir les [mesures DOM](geex-gama-1180-evidence.json).
- À 1440 px : neuf colonnes, barre latérale de 244 px, début du contenu à 276 px, tuiles de 106,4375 px et débordement horizontal nul.
- Le retour conserve son SVG de 24 px ; le dégradé de la barre latérale repose explicitement sur un blanc opaque, sans changement visible du fond.
- Revue finale Impeccable : livraison dans le périmètre borné. Les trois constats identifiés ont été corrigés : chargement de la police, retour à la ligne des titres d’accueil et largeur latérale.

## Captures de la révision

| Surface | Vue |
| --- | --- |
| Accueil PC au seuil de navigation permanente | [1180 px](screens/geex-gama-home-1180.jpg) |
| Dashboard PC | [1280 × 900 px](screens/geex-gama-dashboard-desktop.jpg) |
| Documents PC, fixture vide | [1280 × 900 px](screens/geex-gama-documents-desktop.jpg) |
| Accueil petit téléphone | [320 px](screens/geex-gama-home-320.jpg) |
| Accueil téléphone | [390 × 844 px](screens/geex-gama-home-mobile.jpg) |
| Dashboard téléphone | [390 × 844 px](screens/geex-gama-dashboard-mobile.jpg) |

L’application se trouve à gauche des captures : le navigateur ajoute une zone vide à l’extérieur de son iframe. Les dimensions indiquées décrivent l’application, pas toute l’image. La capture Documents montre un état vide de fixture, sans attester les tableaux remplis ni les parcours de téléchargement.

## Limites

Ces captures et mesures vérifient le cadre partagé et les surfaces nommées. Elles ne constituent pas un contrôle visuel de chaque module, état métier ou langue. Les fonctions et ACL existantes restent conservées par la refonte ; les essais physiques iPhone/Android et les données de production ne font pas partie de cette preuve. La [vérification du 29 octobre](verification-2026-10-29.md) reste historique et décrit la révision précédente.
