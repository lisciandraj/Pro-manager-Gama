# Site public GAMA — Coco ERP / Cloudflare Pages

Le site public est construit séparément de l’ERP. Il présente uniquement les produits actifs sélectionnés dans **Site web → Site public → Produits publiés**. Le site de test historique reste réservé aux administrateurs et conserve ses propres réglages et demandes.

## Paramétrage dans Coco

1. Ouvrir **Site web**, puis **Site public** avec un compte administrateur autorisé.
2. **Identité et apparence** : nom commercial, signature, logo, couleurs, angles et liens du menu. Les images PNG, JPEG et WebP sont comprimées lors du chargement.
3. **Page d’accueil** : bandeau, titres, texte, image, bouton, sélection, catégories et avantages.
4. **Contenu et pages** : présentation, image, FAQ, marques, conditions, confidentialité et pied de page. Les listes peuvent être ajoutées, supprimées et réordonnées.
5. **Contact** : téléphone, e-mail, adresse, horaires, WhatsApp avec indicatif international, carte et réseaux sociaux.
6. **Publication et catalogue** : activer/mettre en pause le site, renseigner son adresse HTTPS, afficher/masquer les prix, choisir l’affichage des taxes, activer les demandes de devis, choisir tri et pagination, titre et description pour les moteurs de recherche.
7. Cliquer **Enregistrer tous les réglages**. Le brouillon est conservé en naviguant entre les rubriques. En cas de conflit avec un autre administrateur, copier les changements nécessaires avant **Actualiser** ; ce bouton recharge les valeurs enregistrées.
8. Dans **Produits publiés**, choisir les produits visibles et les produits mis en avant. Le nom, la référence, la photo, le prix de vente, les taxes et les quantités de commande viennent des Produits de Coco. Le titre, la description, la marque, l’étiquette et le nom public de la catégorie peuvent être adaptés ici. Les produits inactifs sont exclus immédiatement.
9. Dans **Demandes du public**, consulter les coordonnées, produits et quantités, ajouter une note interne et marquer la demande comme traitée ou archivée.

Les prix sont indicatifs. Un prix absent ou nul est présenté comme « Consultar ». Envoyer une demande ne crée ni commande, ni facture, ni réservation de stock. Après vérification, préparer le devis dans le module Ventes avec les coordonnées et quantités reçues. Aucun paiement en ligne ni envoi automatique d’e-mail n’est activé par ce site.

## Première publication sur Cloudflare Pages

### Activer ou désactiver la publication depuis Coco

Dans **Site web → Site public**, le bandeau supérieur affiche l’état réellement enregistré : **Site publié** ou **Publication désactivée**. Cliquer sur **Activer la publication** ou **Désactiver la publication** applique immédiatement le changement, sans re-déployer Cloudflare. Le bouton conserve les autres modifications de formulaire en brouillon ; elles restent à enregistrer avec **Enregistrer tous les réglages**. En cas d’échec, l’état affiché reste celui de la dernière sauvegarde réussie.

Lorsque la publication est désactivée, les visiteurs voient une page de maintenance avec les coordonnées publiques. Le catalogue, les photos de produits et l’envoi de demandes sont bloqués côté serveur. Les produits et les demandes existantes restent disponibles dans l’administration Coco. Le réglage **Publier le site** de **Publication et catalogue** contrôle le même état après enregistrement.

### Configurer l’hébergement

Précondition : la migration `public_storefront` doit être appliquée à Supabase, et l’administration de Coco doit être déployée. Les accès à Cloudflare restent nécessaires pour créer le projet et son secret.

1. Se connecter à Cloudflare et ouvrir **Workers & Pages → Create application → Pages → Connect to Git** (les libellés peuvent évoluer).
2. Autoriser l’accès au dépôt GitHub `lisciandraj/Pro-manager-Gama`, sélectionner la branche `main` et créer un projet nommé `gama-coco` ou un autre nom disponible.
3. Choisir aucun framework, la commande de compilation `npm run build:storefront` et le dossier de sortie `dist-storefront`. Utiliser Node **24** (`NODE_VERSION=24`). Le fichier `wrangler.jsonc` décrit le dossier de sortie et la date de compatibilité ; adapter son nom au nom de projet si nécessaire.
4. Dans Coco : **Site web → Site public → Connexion Cloudflare → Afficher la clé de connexion**. Copier la clé.
5. Dans les paramètres Cloudflare Pages du projet, créer le **secret** `COCO_SITE_TOKEN` avec cette clé pour l’environnement de production. Une prévisualisation acceptant des demandes doit avoir son propre secret configuré. Ne jamais ajouter cette valeur à GitHub, dans un fichier JavaScript public ou dans une variable préfixée `VITE_`.
6. Déployer/re-déployer pour que les Pages Functions disposent du secret. Le dossier `functions/` à la racine contient les points d’entrée ; Cloudflare compile leurs implémentations sous `src/storefront/server/`.
7. Ouvrir l’adresse `https://<projet>.pages.dev`. Vérifier le catalogue, les images, une catégorie et l’affichage sur téléphone. Renseigner cette adresse dans **Publication et catalogue** de Coco puis enregistrer.
8. Envoyer une demande de devis avec des coordonnées de test identifiables, vérifier sa réception dans **Demandes du public**, puis l’archiver. Ne pas utiliser les coordonnées d’un tiers pour cette vérification.
9. Pour un domaine personnalisé : l’ajouter dans **Custom domains** du projet, suivre les instructions DNS Cloudflare, puis remplacer l’adresse du site dans Coco. La migration du domaine existant n’est pas automatique.

Si la réception des demandes indique une connexion manquante, contrôler le secret `COCO_SITE_TOKEN` et re-déployer. Le bouton **Renouveler la clé** invalide immédiatement l’ancienne : remplacer le secret dans Cloudflare puis re-déployer. Le site peut continuer à présenter le catalogue pendant cette opération. Mettre le site en pause dans Coco masque le catalogue et bloque les envois à la base.

La maintenance courante du contenu ne demande aucun re-déploiement : les pages lisent Coco. Les modifications du code, du secret et du domaine restent des opérations d’hébergement dans Cloudflare, puisqu’un compte Cloudflare est nécessaire pour les réaliser.

## Contrat et protection des données

| Échange | Accès | Données |
| --- | --- | --- |
| `gama_storefront` / `bootstrap`, `catalog`, `product`, `photos` | Public | Configuration publique et produits actifs explicitement publiés |
| `/api/storefront` / `submit` | Pages Function, même origine, secret serveur | Demande de devis avec identité de visiteur injectée côté serveur |
| `gama_website` / `public_*` | Administrateur autorisé, droits et MFA vérifiés dans SQL | Réglages, publication, clé et consultation des demandes |

La façade SQL publique utilise `SECURITY INVOKER` ; sa passerelle contrôlée se trouve dans le schéma non exposé `storefront_api`. Le schéma historique `private` n’est pas ouvert au rôle `anon`. Les tables de configuration, clé et demandes ont RLS et aucun droit direct pour les visiteurs. Les coûts d’achat, stocks exacts, fournisseurs, utilisateurs et coordonnées d’autres demandeurs sont exclus du catalogue.

Les demandes contrôlent le consentement, les produits publiés, les quantités minimales et multiples. Coco recalcule les prix et taxes côté serveur. Une clé de requête stable permet de réessayer après une interruption réseau sans doublon. Les limites sont de huit demandes par visiteur sur trente minutes, cinq par adresse e-mail sur une heure et un plafond global quotidien. L’adresse réseau transmise par Cloudflare est transformée en empreinte avec la clé du site et n’apparaît pas dans l’interface administrative. Le formulaire ne mémorise aucune coordonnée personnelle dans le stockage du navigateur ; seuls les identifiants et quantités de la sélection peuvent rester dans la session de l’onglet.

Cloudflare injecte dans le HTML le titre, la description et le premier état public du catalogue. Le JSON est inerte et échappé ; les textes administrés sont rendus comme texte, sans HTML arbitraire. La police est locale, les images sont PNG/JPEG/WebP ou HTTPS, et aucune bibliothèque ERP ni clé serveur n’est livrée dans le site public. Les réponses dynamiques ne sont pas mises en cache pour éviter la publication persistante d’un produit retiré.

## Développement et validation

```sh
npm ci
npm run build
npm run build:storefront
npm run validate
node --test tests/storefront-db.test.cjs tests/storefront-server.test.mjs
npx playwright test tests/storefront.spec.js tests/website-preview.spec.js
```

Les tests SQL restaurent toutes les migrations dans une base PGlite isolée. Les tests navigateur utilisent des fixtures et n’envoient aucune demande dans la base de production. Les tests du proxy contrôlent les actions autorisées, taille du corps, origine, injection de l’identité et du secret, et suppression des erreurs internes. Une vérification après déploiement reste nécessaire pour les Pages Functions, le secret et le domaine réellement utilisés.

Sources canoniques : [schéma des réglages](../config/storefront-schema.json), [site public](../src/storefront/), [administration](../src/features/website/store-admin.js), [compilation](../scripts/build-storefront.cjs). L’URL et la clé **publique** Supabase se trouvent dans [storefront-runtime.json](../config/storefront-runtime.json). La clé d’intégration serveur est exclusivement dans la base privée et le secret Cloudflare.
