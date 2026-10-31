# Geex / GAMA — vérification du 30 octobre 2026

La direction approuvée remplace l’apparence ERP par une reconstruction des captures Geex fournies, avec les couleurs GAMA. Les preuves portent sur le code compilé et des fixtures isolées. Aucun fichier Figma ni code Geex n’a été importé ; aucune publication en production n’est attestée ici. Le [contrat ERP](DESIGN.md) et la [fiche de surface](.impeccable/surfaces/coco-erp.md) décrivent le périmètre.

## Contrôles réalisés

- Validation locale initiale de la refonte : `npm run validate` réussi, 760 tests au total, 758 réussis, 2 ignorés, aucun échec. Ce résultat ne signifie pas que les suites navigateur ont été exécutées localement.
- Les suites navigateur locales ne peuvent pas lancer leur serveur dans cet environnement : refus de socket `EPERM`. La CI `caee` a validé Contacts, audit, architecture, achats, comptabilité et concurrence. Ses contrôles UI ont révélé une ancienne hauteur de cadre masquant les minima d’en-tête, des décalages de panneaux collants, des retraits d’encoche en paysage et un débordement WebKit dans Entrepôts. Les sources ont été corrigées ; la validation CI complète de cette nouvelle révision reste en attente et la PR 274 reste ouverte.
- Après ces corrections, `npm run check`, `npm run typecheck`, `npm run check:docs`, `npm run check:generated`, `npm run check:startup` et 24 tests d’architecture ont réussi.
- Budget de démarrage mesuré : 296 813 octets CSS sur 300 000 ; 14 scripts ; 798 084 octets JavaScript sur 850 000. Aucun plafond n’a été augmenté. Ces poids ne mesurent pas le temps de chargement réseau.
- Poppins régulier, moyen et semi-gras sont livrés localement, pour 28 768 octets WOFF2 au total, avec la licence SIL OFL 1.1 dans `fonts/Poppins-OFL.txt`. La [preuve de chargement](geex-gama-font-evidence.json) indique Poppins chargée ; ses champs réseau ne sont pas un calcul du poids total des fichiers.
- À 320 px après ajustement du palier compact : les 25 tuiles mesurées sont carrées (89,65625 px de côté), aucun titre ne dépasse son carré et le débordement horizontal de page est nul. L’ajustement corrige un dépassement de titre de 1,8 px observé lors de la QA. Voir les [mesures DOM à 320 px](geex-gama-320-evidence.json).
- Mesures initiales : à 1180 px, sept colonnes, barre latérale de 244 px, début du contenu à 276 px et débordement horizontal nul ; titre « Base de connaissances » de 92,5625 px de large sur deux lignes. Voir le [relevé initial](geex-gama-1180-evidence.json). À 1440 px, neuf colonnes et tuiles carrées de 106,4375 px, sans débordement horizontal.
- Contrôle ciblé à 1180 px avec `scrollbar-gutter: stable` : « Base de connaissances » reste complet sur deux lignes (largeur 94,421875 px, hauteur 32,375 px, interligne 16,2 px). À 1440 px dans Ventes, le tableau commence à y = 553 px et le menu Outils partage la rangée des onglets.
- Paysage 932 × 430 px, zones de sécurité gauche 47 px et droite 34 px : retraits du bandeau `16px 58px 16px 71px`, hauteur réelle 97,796875 px et largeur cliente de 917 px. Le bord droit de l’avatar est à 859 px, dans la limite sûre de 898 px. Ces [mesures de correction](geex-gama-corrections-evidence.json) portent sur la compilation récente.
- Le retour conserve son SVG de 24 px ; le dégradé de la barre latérale repose explicitement sur un blanc opaque, sans changement visible du fond.
- Revue finale Impeccable : livraison dans le périmètre borné. Les trois constats identifiés ont été corrigés : chargement de la police, retour à la ligne des titres d’accueil et largeur latérale.

## Captures de la révision

Les premières captures documentent la refonte et le palier compact ; les deux dernières montrent les corrections de disposition suivantes.

| Surface | Vue |
| --- | --- |
| Accueil PC au seuil de navigation permanente | [1180 px](screens/geex-gama-home-1180.jpg) |
| Dashboard PC | [1280 × 900 px](screens/geex-gama-dashboard-desktop.jpg) |
| Documents PC, fixture vide | [1280 × 900 px](screens/geex-gama-documents-desktop.jpg) |
| Accueil petit téléphone | [320 px](screens/geex-gama-home-320.jpg) |
| Accueil téléphone | [390 × 844 px](screens/geex-gama-home-mobile.jpg) |
| Dashboard téléphone | [390 × 844 px](screens/geex-gama-dashboard-mobile.jpg) |
| Accueil avec gouttière de défilement classique stable | [1180 px](screens/geex-gama-home-scrollbar-1180.jpg) |
| Ventes après correction du bandeau et de la rangée Outils | [1440 px](screens/geex-gama-sales-corrections-desktop.jpg) |

L’application se trouve à gauche des captures : le navigateur ajoute une zone vide à l’extérieur de son iframe. Les dimensions indiquées décrivent l’application, pas toute l’image. La capture Ventes est affichée à 90 % pour présenter tout le cadre de 1440 × 1000 px. La capture Documents montre un état vide de fixture, sans attester les tableaux remplis ni les parcours de téléchargement.

## Limites

Ces captures et mesures vérifient le cadre partagé et les surfaces nommées. Elles ne constituent pas un contrôle visuel de chaque module, état métier ou langue. Les fonctions et ACL existantes restent conservées par la refonte ; les essais physiques iPhone/Android et les données de production ne font pas partie de cette preuve. La [vérification du 29 octobre](verification-2026-10-29.md) reste historique et décrit la révision précédente.
