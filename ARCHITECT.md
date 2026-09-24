# COCO ERP — interface de référence

L’ERP s’appelle **Coco ERP** (anciennement Architect ERP). Les identifiants techniques — fichiers `architect-*`, objets `Architect*`, classes `arc*`, identifiants GAMA — ne changent pas : seuls le nom affiché et le logo changent.

L’application reste le site statique `lisciandraj/Pro-manager-Gama`, avec ses modules JavaScript, son authentification et sa base Supabase existants. Aucun framework, route, identifiant de module, schéma ou workflow n’est remplacé.

## Référence visuelle et logo

La maquette fournie de 1145 × 1374 pixels est la référence : sidebar d’environ 192 px, barre supérieure de 70 px, grille principale de cartes blanches compactes de 12 px de rayon. La maquette en montrait quatre par ligne ; l’accueil en place six à partir de 1280 px, pour que tous les modules tiennent sans défiler, et retombe à quatre en dessous, puis trois et deux, là où un libellé de tuile cesserait de se lire d’un coup d’œil. Les couleurs, elles, viennent du logo (voir « Palette »). Les tableaux et champs gardent des séparateurs plus soutenus pour la lisibilité.

`coco-erp-logo.png` est le fichier officiel fourni, copié sans transformation. SHA-256 : `c3e75d1cbbf288bd180c62593ea5bad31c2678986804e6b053c8f3bc6d675f15`. Le logo est dessiné pour un fond blanc ; les variantes sont de simples recadrages de ce fichier, sans retouche des couleurs :

| Fichier | Usage |
|---|---|
| `coco-erp-logo-full.png` | Écran de connexion : logo complet avec le slogan. |
| `coco-erp-wordmark.png` | Barre latérale, sur une carte blanche : « COCO ERP » sans le slogan, illisible à cette taille. |
| `coco-erp-icon-512/192/180.png` | Icône d’application (manifeste, favicon, écran d’accueil iOS) et barre latérale repliée : le robot seul, sur fond blanc. |

La barre latérale est blanche, comme la barre supérieure, et séparée du fond gris par un filet : le logo, dessiné pour un fond blanc, s’y pose tel quel, sans carte ni détourage. Les liens sont en bleu nuit, l’élément actif sur un fond bleu très clair avec un filet bleu à gauche.

## Palette

Toutes les couleurs de l’interface sont tirées du logo et vivent dans `architect-tokens.css`. Relevés dans `coco-erp-logo.png` : bleu du robot `#3B6CF9` (dégradé `#3BA3FE` → indigo `#3E3AD9`), visière `#293051`, violet `#925396`, turquoise `#3FB3A4`, orange `#FCAA27`.

| Rôle | Token | Couleur | Origine |
|---|---|---|---|
| Barre latérale et barre supérieure | `--arc-surface` | `#FFFFFF` | le fond pour lequel le logo est dessiné |
| Liens de la navigation | `--arc-navy-700` | `#323A6B` | visière du robot : 10,8:1 sur blanc |
| Élément actif de la navigation | `--arc-accent-100` / `--arc-accent-700` | `#E4EBFE` / `#2446B8` | bleu du robot : 6,7:1 |
| Fond de connexion, bulles de l’assistant | `--arc-navy-800` / `--arc-navy-900` | `#1F2442` / `#262C4E` | visière du robot |
| Action principale : boutons, liens, sélection | `--arc-accent-600` | `#2D59DB` | bleu du robot assombri : 5,9:1 sur blanc |
| Décor et anneau de focus | `--arc-accent-500` | `#3B6CF9` | bleu du robot |

### Les quatre lettres de COCO

Les seules familles de couleur de l'application sont les quatre lettres du logo, relevées dans `coco-erp-wordmark.png` (`--arc-coco-*`). Chaque module, indicateur ou série de graphique en porte une, selon son domaine :

| Lettre | Couleur du logo | Domaine | Icône (sur fond teinté) | Texte (≥4,5:1) |
|---|---|---|---|---|
| C | bleu `#3B6CF9` | Pilotage : tableau de bord, assistant IA, suivi de processus, projets, documents, base de connaissances, import | `#3B6CF9` sur `#E0E7FE` | `#2D59DB` |
| O | violet `#905494` | Ventes et clients : devis et factures, CRM, contacts, tarifs, SAV, catalogue, livraisons client | `#905494` sur `#EDE4EE` | `#905494` |
| C | turquoise `#3CB4A4` | Stock, achats et logistique : produits, entrepôts, entrées/sorties, achats, matrice, codes-barres, livraison, retours, flotte | `#319386` sur `#E0F3F0` | `#2B8276` |
| O | orange `#FCA824` | Administration : comptabilité, RH, utilisateurs, paramètres d'accès, configuration, audit, sauvegardes | `#BF7603` sur `#FFF1DC` | `#A86802` |

La famille se déclare par module dans `src/app/registry.js` (`accent`: `blue`, `violet`, `teal`, `orange`). Les anciens noms (`cyan`, `green`, `indigo`, `pink`, `red`) restent des alias qui tombent sur l'une des quatre. Les séries de graphique `--arc-viz-1` à `4` suivent le même ordre que les lettres.

Les couleurs vives du logo ne se lisent pas toutes telles quelles : le turquoise fait 2,5:1 sur blanc, l’orange 1,9:1 ; le bleu et le violet, eux, servent tels quels pour les icônes. L’interface en garde la teinte et les assombrit jusqu’à 4,5:1 au moins ; les icônes des tuiles gardent 3:1 sur leur fond teinté. Les gris — bordures, textes secondaires — tirent vers la teinte du bleu à luminance égale, si bien qu’aucun contraste n’a baissé. Succès, alerte et erreur gardent leurs couleurs fonctionnelles, toujours accompagnées d’un texte ou d’une icône.

Les documents imprimés (devis, factures, bons) n’en dépendent pas : ils suivent les couleurs choisies par l’entreprise dans sa configuration.

La police Inter est hébergée localement dans `fonts/`, avec sa licence OFL, pour un rendu stable sans requête externe.

## Sources partagées

- `architect-tokens.css` : couleurs, espaces, rayons, ombres et typographie. Les alias publics `--color-*`, `--radius-*`, `--shadow-*` réutilisent ces tokens.
- `architect-ui.css` : cartes, tableaux, champs, boutons, états, dialogues et notifications communs aux modules existants.
- `architect-shell.css` : sidebar, barre supérieure, profil, navigation responsive.
- `architect-home.css` : accueil, grille, activité et personnalisation.
- `architect-home-kpis.js` et `architect-kpis.css` : les quatre indicateurs personnels, en tête du tableau de bord.
- `architect-shell.js` : navigation depuis `GamaMenu`, recherche globale existante, déplacement des contrôles de session existants dans le menu utilisateur, indicateur actif, droits et langues.
- `gama-menu-final2.js` : registre de tous les modules existants, cartes et activité. TMS utilise désormais ce même registre ; son chargeur reste unique.

Les feuilles de la sidebar et de l’accueil remplacent les anciennes chaînes CSS injectées. Les feuilles partagées habillent les classes déjà utilisées par les modules, y compris les composants chargés tardivement. Les nouvelles préférences d’affichage restent locales au navigateur et séparées des données métier.

## En-tête de module

Chaque écran s’ouvre sur l’en-tête standard produit par `ArcUI.header()`. Il porte l’icône de son propre module : le même dessin et le même accent que la tuile qui y mène depuis le menu, pour que l’on reconnaisse d’où l’on vient.

Les deux surfaces lisent la même source, `ArcModules.registry` pour `icon` et `accent`, et `ArcUI.icons` pour le tracé. Un module qui change d’icône change des deux côtés à la fois ; il n’y a rien à tenir à jour écran par écran, et aucun fichier de module n’a été modifié pour cette uniformité.

`header()` laisse une case vide, `<span class="gamaStdIcon" data-arc-icon-slot>`, que `ArcUI.headerIcon(racine, id)` remplit. Le module est identifié dans cet ordre : `data-arc-module`, posé quand l’appelant passe `module` ; l’`id` explicite ; enfin l’`id` de la `<section>` qui contient l’en-tête, que trente-cinq écrans sur trente-sept portent déjà. `gama-tms-section` est la seule exception, traitée par un alias ; le tableau de bord passe son identifiant explicitement parce qu’il peint son en-tête lui-même.

Trois points de peinture couvrent tous les écrans : `ArcRouter.show()` pour les modules du registre, `bindBack()` dans `gama-ui.js` pour les écrans écrits à la main dans `index.html`, et l’appel propre au tableau de bord. Un en-tête relié avant d’être accroché à sa section ne sait pas encore de quel module il est : la peinture est alors relancée une fois au tick suivant.

L’interface n’utilise aucun emoji : ni dans les titres, ni sur les boutons, ni dans les messages. Les seuls dessins sont ceux de l’application, tirés de `ArcUI.icons` : tuiles du menu, navigation latérale, en-tête de chaque module, rubriques des fenêtres Configuration et Notifications, et les emplacements « sans photo » (le cube de Produits, la voiture ou le camion de la Flotte). Un titre qui arriverait encore avec un pictogramme en tête le perd dans `header()`, et le catalogue de traduction indexe le texte sans ornement. `tests/no-emoji.spec.js` vérifie les sources et chaque écran.

Les onglets des modules n’ont pas d’icône : un onglet porte son nom, et les modes (Importer des données) comme les bascules Actifs / Archivés sont en texte seul. Seules les rubriques des fenêtres Configuration et Notifications ont leur dessin, comme les tuiles du menu ; les rubriques de Notifications gardent en plus leur compteur. `tests/tab-labels.spec.js` le vérifie.

Les teintes d’accent des tuiles du menu sont limitées à `#mainmenu`. L’en-tête a donc ses propres règles `.gamaStdIcon[data-arc-fam=…]` dans `src/ui/module-styles.css`, appuyées sur les mêmes jetons `--arc-icon-*`, sans toucher aux feuilles du menu ni à celles des réglages.

## Données de l’accueil

L’accueil ne contient aucune donnée de démonstration.

- Facturation du mois : `gama_operations_action(snapshot).metrics.invoiced`, lorsque `finance` est autorisé. Il s’agit de factures TTC, donc le libellé précise « Facturation » et « TVA incluse ».
- Commandes confirmées du mois : `metrics.orders`.
- Livraisons en retard : `metrics.late_deliveries`.
- Clients actifs : décompte exact des clients actifs, sous les droits existants.

`total` et `active_count` de cette RPC sont des compteurs d’alertes et ne doivent jamais être utilisés comme chiffre d’affaires ou commandes. Une donnée indisponible ne devient pas artificiellement zéro. Aucun taux d’évolution n’est inventé en l’absence d’une série de comparaison.

L’activité récente affiche les quatre derniers mouvements réels de l’audit de stock déjà synchronisé. Elle est réservée aux profils autorisés à consulter l’audit. Le lien ouvre l’audit complet. Il ne s’agit pas d’un journal universel de tous les modules.

## Navigation et droits

Desktop à partir de 1100 px : sidebar permanente. Tablette de 861 à 1099 px : rail d’icônes extensible. Jusqu’à 860 px : tiroir mobile, fermé hors de l’ordre de tabulation avec `inert`, ouvert au clavier avec focus maintenu dans la navigation. Échap ferme le tiroir et rend le focus au bouton.

Téléphone couché : la page va jusqu’aux bords de l’écran (`viewport-fit=cover`). Les marges de sécurité `--arc-safe-l`, `--arc-safe-r` et `--arc-safe-b` (`env(safe-area-inset-*)`, nulles hors encoche) décalent la navigation, la barre, le contenu et les fenêtres plein écran. Les fenêtres à menu latéral (Configuration, Notifications) passent en plein écran, rubriques en rangée, dès que la largeur ou la hauteur est faible (≤ 760 px de large ou ≤ 520 px de haut).

Formulaires : une case qui contient un champ peut toujours rétrécir (`min-width:0`). Safari (iPhone, iPad, Mac) compte la largeur naturelle d’un champ — une date, une liste aux options longues — et élargissait sinon la colonne, jusqu’à déborder de la carte ou de la page. Sur iPhone et iPad, dates et heures perdent leur apparence native, qui leur imposait une largeur minimale ; le sélecteur du système s’ouvre toujours. `tests/responsive-forms.spec.js` imite la mesure de Safari et vérifie la Matrice commerciale, la planification des Livraisons, la fiche entreprise et les règles RH à 390×844, 844×390, 932×430 et 1024×768.

La sidebar présente les destinations principales puis « Autres modules ». Tous les modules restent dans le registre et sur l’accueil. « Personnaliser » permet de masquer des cartes uniquement sur l’accueil ; les destinations restent accessibles dans la navigation. Les préférences sont propres au profil local et n’accordent jamais un droit d’accès.

La barre supérieure porte deux boutons d’icône identiques : la cloche des notifications et, juste à sa droite, la roue de la configuration. Ni l’une ni l’autre n’est une tuile de l’accueil ou un lien de la sidebar (`topbar: true` dans le registre), mais `ArcRouter.open('settings')` et la recherche l’ouvrent toujours.

La roue ouvre une fenêtre modale (`#arcSettingsDialog`, `gama-settings.js`) avec un menu latéral de rubriques : Langue, Informations sur l’entreprise, Identité des documents, Réglages fiscaux, Références des documents, Règles opérationnelles et Sécurité de mon compte. Seules la langue et la sécurité du compte sont proposées à qui n’est pas administrateur. Le menu est un `tablist` vertical (flèches, Début, Fin) ; sur téléphone la fenêtre occupe l’écran et les rubriques se mettent en rangée défilante en haut. Chaque rubrique se charge la première fois qu’on l’ouvre. Les trois rubriques de l’entreprise restent une seule fiche avec un seul « Enregistrer » : chacune n’affiche que ses cartes (`data-co-section`), et un champ obligatoire d’une autre rubrique y ramène avant que le navigateur ne le signale. `GamaSettings.open('fiscal')` ouvre directement une rubrique. Les couleurs des documents PDF restent celles choisies dans « Identité des documents ». Les « Paramètres d’accès » (modules et profils) restent un module à part.

La cloche ouvre de la même façon la fenêtre Notifications : « Toutes les alertes », puis une rubrique par catégorie du centre d’action avec son compteur (rouge si urgent, orange sinon, rien à zéro), puis Projets, Validations et Préférences. Les deux fenêtres partagent le même composant, `ArcUI.sideDialog` (`src/ui/components.js`) : menu latéral au clavier, rubriques chargées à la demande, fermeture quand on ouvre un autre écran (un dossier, Comptabilité…) pour que la destination soit visible, retour du focus sur le bouton de la barre.

`gama-fixed-header.js` reconnaît le conteneur Architect : il ne déplace plus les contrôles de session vers l’ancienne barre désormais invisible. Déconnexion et gestion des comptes conservent leurs événements et permissions.

Les libellés sont traduits avec le catalogue existant FR/EN/ES. Après modification, exécuter `python3 scripts/build-i18n.py`.

## Vérification

Site statique : pas de compilation, TypeScript ou lint configurés. Vérifier la syntaxe des scripts et des scripts intégrés, les assets locaux, puis les tests Node et Playwright existants. `tests/architect-reference.spec.js` couvre le logo exact, les vrais champs des KPI, les traductions, le profil, la personnalisation, les droits client et le tiroir. `tests/architect-shell.spec.js` contrôle les six largeurs demandées : 1920, 1440, 1024, 768, 430 et 390 px, dont plusieurs écrans de modules.

Les anciennes assertions imposant un fond gris foncé ont été alignées sur la nouvelle référence explicitement demandée. Les séparateurs de tableaux et les champs continuent à utiliser `--arc-line` et `--arc-line-strong` ; les bordures des cartes d’accueil utilisent le token distinct `--arc-card-border`.
