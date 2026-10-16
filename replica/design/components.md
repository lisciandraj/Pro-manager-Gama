# Contrat des composants Coco

Les motifs Odoo guident l’organisation et la densité. Coco garde son logo, ses illustrations, sa typographie Inter et ses accents pétrole/orange. Le projet n’utilise pas Tailwind : les rôles de `tokens.json` sont mappés aux variables CSS historiques `--arc-*` dans `tokens.css`, puis aux sources runtime. Aucun framework ni dépendance supplémentaire.

| Composant | Règles et états |
| --- | --- |
| En-tête | Titre 24 px/700, séparation fine, outils dans la même zone. Retour visible. Outils étroits dans le panneau natif existant, sans déplacer les cinq sections Ventes. En dessous de 1100 px, actions réparties sur une ligne supplémentaire. |
| Bouton | Cible 44 px minimum, libellé explicite. Primaire pétrole foncé + blanc ; survol plus sombre ; focus contour 2 px décalé de 3 px. Disabled natif et état occupé existant conservés. |
| Champ | Étiquette persistante 12 px/600, hauteur existante 44 px, bordure #778695 sur blanc. Placeholder lisible. Lecture seule grisée, erreur textuelle + bordure rouge + aria-invalid. Texte 16 px sur téléphone. Valeurs et aide conservées en cas d’erreur. |
| Onglets | Libellé, sélection et focus conservés. Sections Ventes toujours visibles, retour à la ligne sur téléphone. Aucun remplacement par un menu de navigation. |
| Tableau | Quadrillage visible, en-tête 12 px/600, cellules 13 px, montants tabulaires. Survol bleu très clair et sélection bleu clair. Colonnes, tri et vue personnelle gérés par GamaTable sans nouvelle clé. Défilement limité au tableau. États vide/erreur/pagination existants. |
| Carte CRM | Titre 14 px, montant 16 px, séparateurs fins, rayon 6 px. Étape identifiée par texte et couleur. Cible de déplacement ≥44 px ; état glissé avec bordure pointillée ; retard marqué et libellé ; erreurs de mutation conservent la carte. |
| Bibliothèque Documents | Rail 210 px, 180 px sur tablette ; contenu minmax(0,1fr). Recherche dans le contenu pour éviter son déplacement hors de la grille par GamaTable. Sur téléphone : rail au-dessus, champs sur deux colonnes si possible. Le titre d’un fichier et sa référence sont hiérarchisés. |
| Article | Rail 240/210 px, fond de lecture blanc, titre 25 px, texte 15 px avec interligne 1.75 et largeur 78ch maximum. Arbre et article empilés sous 760 px. |
| Dialogue | Titre et corps séparés, rayon 12 px, padding 24/16 px. Actions dans un pied distinct, dans le flux pour ne pas recouvrir les champs des longs formulaires. Retour et action métier gardent leurs gestionnaires, échec réseau garde le brouillon, validation amène le focus sur le premier champ invalide. Aucun bouton de fermeture redondant. |
| Badge/alerte | Libellé obligatoire ; success/warning/danger/info sémantiques. Orange de marque avec texte bleu nuit. Ne pas utiliser blanc sur orange pour du texte courant. |

Les lignes décoratives #D8E2EA ne portent pas seules une information interactive. Les bordures de champs et le focus sont contrôlés à 3:1 ; texte courant à 4.5:1. `contrast.json` enregistre les 17 couples du contrat. Les tests navigateur complètent ces mesures avec les styles réellement calculés.

La planche de primitives est rendue avec les composants ArcUI existants sur une page locale de test. Les images de référence et les données de démonstration ne sont pas chargées par l’application publiée. Les animations existantes respectent `prefers-reduced-motion` ; l’accès au formulaire produit suit également cette préférence.

Les styles propres au pipeline CRM, à Documents et à la base de connaissances sont chargés avec leurs modules via le registre de chargement différé. Cela conserve le budget CSS de démarrage ; `config/runtime-assets.json` reste la source des assets publiés.
