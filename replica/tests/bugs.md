# Retours de vérification

| Constat | Cause | Résolution | Vérification |
| --- | --- | --- | --- |
| Résultats Documents repoussés sous les filtres | GamaTable déplaçait la recherche entre les deux enfants de la grille | Recherche rendue à l’intérieur du contenu, dans son hôte stable | Nouveau parcours de recherche/catégorie et alignement desktop/mobile validé |
| Création et enregistrement d’un produit avaient le même libellé | Le nouveau bouton de navigation reprenait le texte du bouton métier | « Nouveau produit » traduit FR/ES/EN ; « Créer produit » reste l’action métier existante | Fournisseur, prix d’achat/vente et parcours nouveau/édition validés |
| Pied de dialogue fixe au-dessus de champs sur téléphone | Le pied sticky recouvrait les contrôles d’un long formulaire | Pied distinct dans le flux normal | Scénario TMS et Documents validé de 320 à 1440 px |
| Dashboard plus large que l’écran sous WebKit à 320 px | Les sélecteurs natifs à 16 px débordaient de leurs colonnes de 140 px en anglais et espagnol | Base flexible de 190 px pour empiler les sélecteurs quand nécessaire, sans réduire le texte | Mesure après correction : page de 320 px en FR/EN/ES |

Aucun bug bloquant restant dans les parcours navigateur exercés. La liste ne constitue pas un audit complet de tous les modules ou navigateurs. Les suites de production ne sont pas exécutées contre de vraies données.
