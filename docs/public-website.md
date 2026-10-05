# Site public GAMA — Coco ERP / Cloudflare Pages

Le site public est construit séparément de l’ERP. Tous les produits actifs sont sélectionnés par défaut. Il présente uniquement les produits actifs sélectionnés dans **Site web → Site public → Produits publiés**. Le site de test historique reste réservé aux administrateurs et conserve ses propres réglages et demandes.

## Présentation du catalogue

Depuis le 4 octobre 2026, l’accueil commence par les catégories : une tuile blanche avec photo au-dessus du titre, bordure fine et nombre de produits. Les trois colonnes sur téléphone et six sur grand écran reprennent le modèle de navigation fourni, avec le logo GAMA, le bleu pétrole et les actions orange. Les catégories, photos et libellés viennent des produits publiés ; aucune gamme fictive n’est ajoutée.

La recherche est permanente dans l’en-tête. La saisie et la touche Entrée filtrent le catalogue et amènent aux résultats. Le menu **Categorías** ouvre un panneau accessible avec les catégories réelles et les liens configurés. La sélection d’une catégorie ferme le panneau et met à jour les filtres ; Échap ferme le menu et rend le défilement à la page.

Le catalogue affiche par défaut une liste structurée : photo, nom, référence/marque, description, lien vers les spécifications, prix indicatif, quantité et **Añadir**. Deux boutons permettent de passer en grille sans perdre les filtres. La quantité respecte les minimums et multiples de Coco ; une confirmation apparaît sans ouvrir ni déplacer le formulaire de devis. Le détail reprend les spécifications disponibles et suggère au maximum deux autres produits publiés de la sélection. La disponibilité et la livraison restent à confirmer par GAMA. Le site conserve les textes et réglages administrés, l’absence de paiement en ligne et le parcours de demande de devis.

Les contrôles de navigation, de quantité et de disposition se trouvent dans `tests/storefront.spec.js`, sur 320, 390 et 1440 pixels. Les fixtures n’écrivent pas dans la production.

## Paramétrage dans Coco

1. Ouvrir **Site web**, puis **Site public** avec un compte administrateur autorisé.
2. **Identité et apparence** : nom commercial, signature, logo, couleurs, angles et liens du menu. Les images PNG, JPEG et WebP sont comprimées lors du chargement.
3. **Page d’accueil** : bandeau, titres, texte, image, bouton, sélection, catégories et avantages.
4. **Contenu et pages** : présentation, image, FAQ, marques, conditions, confidentialité et pied de page. Les listes peuvent être ajoutées, supprimées et réordonnées.
5. **Contact** : téléphone, e-mail, adresse, horaires, WhatsApp avec indicatif international, carte et réseaux sociaux.
6. **Publication et catalogue** : activer/mettre en pause le site, renseigner son adresse HTTPS, afficher/masquer les prix, choisir l’affichage des taxes, activer les demandes de devis, choisir tri et pagination, titre et description pour les moteurs de recherche.
7. Cliquer **Enregistrer tous les réglages**. Le brouillon est conservé en naviguant entre les rubriques. En cas de conflit avec un autre administrateur, copier les changements nécessaires avant **Actualiser** ; ce bouton recharge les valeurs enregistrées.
8. Dans **Produits publiés**, choisir les produits visibles et les produits mis en avant. Le nom, la référence, la photo, le prix de vente, les taxes et les quantités de commande viennent des Produits de Coco. Le titre, la description, la marque, l’étiquette et le nom public de la catégorie peuvent être adaptés ici. Les produits inactifs sont exclus immédiatement.
9. Dans **Ventes → Demandes clients**, consulter les demandes du site, associer ou créer le contact si nécessaire, puis préparer le devis.

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

Cloudflare injecte dans le HTML le titre, la description et le premier état public du catalogue. Le JSON est inerte et échappé ; les textes administrés sont rendus comme texte, sans HTML arbitraire. La police est locale, les images sont PNG/JPEG/WebP ou HTTPS, et aucun module métier ERP ni clé serveur n’est livré dans le catalogue public. Le portail B2B séparé charge uniquement les bibliothèques Auth et PDF nécessaires. Les réponses dynamiques ne sont pas mises en cache pour éviter la publication persistante d’un produit retiré.

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

Le module **Site web** ouvre uniquement **Site public**. Les anciens onglets Présentation, Catalogue et Demandes de test et le lien vers le site de test ont été retirés du module. Les réglages et produits du site public restent disponibles dans Site public, ainsi que le bouton de publication. Les demandes se traitent dans Ventes → Demandes clients. Aucun réglage de publication ni aucune donnée historique ne sont modifiés par ce nettoyage.

## Demandes clients

Les envois publics alimentent directement Ventes → Demandes clients avec les lignes et montants hors taxes calculés côté serveur, la référence WEB et les coordonnées d’origine. Un e-mail ou un nom exact (casse et espaces normalisés) correspondant à un seul client actif permet le rattachement automatique. Plusieurs correspondances restent à identifier par un collaborateur. Aucun renseignement du fichier clients n’est renvoyé au visiteur.

Une demande sans client propose **Associer ou créer un contact** : sélectionner un client, ou créer sa fiche avec son identification et son délai de paiement. La création et le rattachement sont atomiques et contrôlent les doublons à nouveau. Le nom, l’e-mail et le téléphone viennent de la demande. Cela ne crée aucun compte de connexion ni n’envoie d’e-mail. Les demandes ne créent ni commande ni mouvement de stock. Les envois répétés avec la même clé ne créent qu’une demande. Les demandes publiques historiques sont reprises une seule fois ; les anciennes demandes de test restent exclues.

Le suivi des demandes publiques est retiré de Site public : leur traitement se fait dans Demandes clients.

## Visibilité des produits

Tous les produits actifs existants sont sélectionnés pour le site à l’installation de cette mise à jour. Les nouveaux produits actifs sont sélectionnés automatiquement. Dans **Site web → Site public → Produits publiés**, cocher ou décocher une ligne enregistre immédiatement sa visibilité sans modifier le titre, la description ou les autres réglages. En cas d’échec, la case revient à sa valeur enregistrée et une erreur s’affiche. Une modification concurrente nécessite une actualisation. Un produit décoché reste masqué après archivage et réactivation. Le bouton général de publication du site reste indépendant.

## Portail entreprises B2B

Le lien **Mi empresa** ouvre le portail espagnol, sur mobile et ordinateur. La source canonique est `src/storefront/b2b.html/js/css`. La compilation publie `gama-b2b.html` avec l’ERP GitHub Pages et `b2b.html` dans le paquet Cloudflare. Le bouton d’administration ouvre la page publiée avec l’ERP. Le lien Mi empresa du site Cloudflare devient disponible après republication de son paquet contenant `b2b.html`. Le SDK Auth local et le générateur PDF sont chargés à la demande. Le site public conserve son accès anonyme ; seul le portail nécessite une connexion.

Dans **Site web → Site public → Portal B2B**, l’administrateur active la catégorie d’accès pour chaque entreprise, invite un nouveau compte ou associe explicitement un compte client existant. Les catégories tarifaires A/B/C restent indépendantes. L’invitation présente entreprise, nom, e-mail, objet et message avant l’envoi explicite. L’Edge Function vérifie les droits Site web, Contactos et Utilisateurs avant d’inviter, puis crée une association avec le jeton de l’administrateur. Une invitation envoyée dont l’association échoue demande une vérification manuelle, sans nouvel envoi automatique. Le lien d’invitation utilise la route de définition de mot de passe autorisée de l’ERP, puis ouvre le portail.

Chaque compte voit les prix calculés pour son entreprise, ses sélections favorites, ses demandes, ses factures PDF/XML autorisées ou pièces enregistrées, ses preuves de livraison et son état de compte PDF. Les favoris reconstituent la sélection, puis les prix doivent être revus avant l’envoi. Les factures et preuves utilisent la référence ERP dans leurs titres et fichiers. Les preuves montrent photo, signature et date/GPS lorsqu’ils ont été enregistrés ; elles ne reconstituent pas une position absente.

Une sélection envoyée crée une demande réelle dans Ventes → Demandes clients ; le traitement commercial et le contrôle du crédit interviennent lors de la confirmation du pedido. Les prix, taxes, quantités et adresse sont revalidés côté serveur. La même clé peut être réessayée après une interruption sans dupliquer la demande. L’adresse d’agence choisie est conservée jusqu’au devis puis au TMS.

La sécurité repose sur `b2b_customer_access` et `b2b_memberships`, jamais sur une correspondance d’e-mail. Les profils `cliente` restent inactifs dans l’ERP : ses restrictions de tables, Storage et anciennes RPC ne sont pas rouvertes. Les façades `gama_b2b_action` vérifient connexion réelle, e-mail confirmé, absence de bannissement, MFA si inscrit, entreprise active, catégorie activée et association active à chaque opération. Les téléchargements SRI contrôlent la propriété avant de signer une URL privée de 60 secondes. Une révocation efface les données affichées et la session du portail. Aucun coût d’achat, fournisseur ou document d’une autre entreprise n’est exposé.

Tests isolés : `tests/ec-b2b-management-stock-db.test.cjs`, `tests/identity-admin.test.mjs`, `tests/sri-openapi-edge.test.cjs`. Parcours navigateur : `tests/b2b-portal.spec.js` et `tests/storefront.spec.js`. Les tests n’envoient aucune invitation et ne créent aucune demande réelle en production.
