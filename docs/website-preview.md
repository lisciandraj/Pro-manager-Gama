# Site web GAMA — version de test

Adresse : `gama-site.html` sur le même hébergement que Coco ERP. Ouvrir Administration → Site web → Ouvrir le site de test, avec une session administrateur active. La page autonome utilise le client Supabase existant, sans charger les écrans de l’ERP. Elle porte `noindex,nofollow,noarchive`.

Le module apparaît dans Administration pour les administrateurs. Il permet de changer le titre, la présentation et les coordonnées, de suspendre la prévisualisation, de masquer les prix, de sélectionner les produits, de définir les produits mis en avant et leurs descriptions web, et de lire les demandes de test.

La migration sélectionne jusqu’à douze produits actifs, en donnant priorité aux produits avec photo. Cette sélection reste privée : aucun accès anonyme au catalogue n’est accordé. Le site reprend le logo GAMA présent dans le dépôt et les coordonnées publiques connues, modifiables dans le module. Les noms, catégories, références, photos et prix proviennent des produits actuels de Coco ; les références et prix de l’ancien site ne sont pas importés.

Les demandes sont enregistrées dans `private.website_inquiries`, avec une référence `WEB-TEST-xxxxxxxx`, des lignes calculées côté serveur et le marqueur obligatoire `is_test=true`. Aucun client, devis commercial, commande, facture, paiement, email ou mouvement de stock n’est créé. Les demandes se consultent et se marquent traitées dans le module Site web. Le passage à un site public et aux commandes réelles fera l’objet d’une évolution distincte.

## Contrôles

- RPC public invoker et implémentation definer privée à `search_path` vide.
- Session active, rôle administrateur, module installé, restrictions de profil et MFA vérifiés côté serveur. Les lectures du catalogue exigent aussi les droits Produits.
- Permissions d’action vérifiées pour les modifications et envois ; version attendue pour les réglages et publications produit.
- Tables privées sans accès direct client, avec RLS activé ; aucun droit RPC anonyme.
- Catalogue paginé, recherche et catégories filtrées ; photos chargées séparément et uniquement pour les produits sélectionnés.
- Contact, quantité, minimum/multiple et sélection des produits contrôlés. Prix et taxes calculés dans la base. Un identifiant d’envoi lié à l’acteur et au contenu empêche les doublons et reste identique après une erreur réseau.
- Textes insérés en contenu échappé, images limitées aux données PNG/JPEG/WebP, panier en mémoire, purge des données affichées au changement de session.

## Validation

`tests/website-preview-db.test.cjs` restaure les migrations réelles et vérifie le cloisonnement, les conflits, les demandes, les prix, les doublons et l’absence d’effets commerciaux.

`tests/website-preview.spec.js` couvre le module, la sélection des produits, la recherche du site, l’envoi avec reprise et la boîte des demandes à 390 et 1280 pixels, ainsi que les accès refusés et la suspension. Ces tests navigateur utilisent une API simulée ; ils complètent les tests de la base.
