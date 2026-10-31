# Coco ERP — surface Geex / GAMA

- **Mode :** operate sur le produit existant, avec remplacement de l’apparence explicitement demandé et direction approuvée le 30 octobre 2026.
- **Autorité :** captures Geex fournies par le propriétaire et demande de reprendre leur apparence avec l’orange et le bleu pétrole GAMA. Les captures guident composition, densité et matière ; l’implémentation est une reconstruction écrite pour Coco. Aucun fichier Figma ni code Geex n’a été acquis ou importé.
- **Périmètre :** application interne `src/app/index.html`, cadre partagé, accueil, surfaces et finitions différées CRM, Projets, Knowledge et Documents. Le site public, son `PRODUCT.md`, son `DESIGN.md` et sa sidecar racine restent distincts.
- **Contrat :** [DESIGN.md ERP](../../DESIGN.md) et [sidecar](../design.json), dérivés des sources runtime ; les anciennes captures et vérifications datées restent des preuves de leurs révisions.

## Expression choisie

Navigation PC flottante de 244 px à 16 px du bord, contenu à 276 px, en-tête ample de 112 px avec titre unique, description traduite et recherche complète. Toile lavande claire, Poppins locale, panneaux blancs de 22 px, cadre latéral et fenêtres de 28 px, contrôles de 12 px, ombres discrètes. Les onglets natifs restent dans le contenu. L’orange de marque GAMA et le pétrole remplacent les accents de la référence ; les actions à texte blanc gardent leur orange sombre accessible.

## Contraintes durables

- Conserver modules, ACL, données, calculs, formulaires, filtres, liens, langues, favoris, ordre personnel et historiques existants.
- Sous 1180 px : tiroir avec focus retenu, Échap, retour de focus et arrière-plan inerte. Conserver la navigation basse mobile et les zones de sécurité.
- Les panneaux collants suivent la hauteur réelle du bandeau ; ses retraits gauche/droite intègrent les zones de sécurité, y compris en paysage avec encoche.
- Accueil : sept colonnes de 1180 à 1439 px, neuf dès 1440 px, trois jusqu’à 760 px ; tuiles carrées et libellés complets sans débordement de page.
- Jusqu’à 359 px : garder trois colonnes avec un intervalle de 6 px, un retrait de page de 12 px plus les zones de sécurité, des icônes de 28 px, des titres de 11 px à interligne 1,25 et une marge intérieure de tuile de 6 px / 2 px. Les titres restent complets dans leur carré.
- Garder la cible tactile de 44 px des contrôles partagés, le focus visible, les statuts écrits, la saisie mobile à 16 px et les préférences de mouvement/contraste.
- Les tableaux larges défilent localement ; les préférences de vue restent prioritaires. Les grilles éditables et fenêtres gardent leurs contrôles métier.

## Revue et preuve

Le reviewer Impeccable conclut à la livraison dans le périmètre borné après résolution des trois constats : chargement Poppins, retour à la ligne des libellés et largeur latérale. Voir la [vérification du 30 octobre](../../verification-2026-10-30.md) pour les captures, mesures et limites. Cette conclusion n’atteste ni une publication en production ni une inspection visuelle de tous les modules.
