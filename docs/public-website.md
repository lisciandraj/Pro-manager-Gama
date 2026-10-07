# Site public GAMA — Coco ERP / Cloudflare Pages

Le site public est construit séparément de l’ERP. Tous les produits actifs sont sélectionnés par défaut. Il présente uniquement les produits actifs sélectionnés dans **Site web → Site public → Produits publiés**. Le site de test historique reste réservé aux administrateurs et conserve ses propres réglages et demandes.

## Présentation du catalogue

Depuis le 7 octobre 2026, l’accueil présente une introduction sobre, des photos de produits réels, les avantages du service, les catégories puis les produits mis en avant. L’en-tête blanc conserve la recherche, le menu, Mi empresa et la sélection de devis. Le logo, le bleu pétrole et l’orange de GAMA restent les repères de la marque. Les catégories défilent dans leur propre conteneur : trois tuiles visibles sur téléphone, six sur grand écran. Le catalogue et les champs longs restent contenus dans la largeur de l’écran.

La recherche est permanente dans l’en-tête. La saisie et la touche Entrée filtrent le catalogue et amènent aux résultats. Le menu **Categorías** ouvre un panneau accessible avec les catégories réelles et les liens configurés. La sélection d’une catégorie ferme le panneau et met à jour les filtres ; Échap ferme le menu et rend le défilement à la page.

Le catalogue affiche par défaut une grille sobre : photo, nom, référence/marque, prix indicatif, quantité et **Añadir**. Deux boutons permettent de passer à une liste détaillée sans perdre les filtres. La liste expose aussi la description, les informations de disponibilité et le lien vers les spécifications. La quantité respecte les minimums et multiples de Coco ; une confirmation apparaît sans ouvrir ni déplacer le formulaire de devis. Le détail reprend les spécifications disponibles et suggère au maximum deux autres produits publiés de la sélection. La disponibilité et la livraison restent à confirmer par GAMA. Le site conserve les textes et réglages administrés, l’absence de paiement en ligne et le parcours de demande de devis.

Les contrôles de navigation, de quantité et de disposition se trouvent dans `tests/storefront.spec.js`. Le catalogue complet de 13 catégories et les champs produit longs sont vérifiés sur 320, 360, 390, 430, 600, 768, 1024 et 1440 pixels, en liste, grille, fiche produit et formulaire de devis. Les filtres de catégories défilent horizontalement dans leur propre conteneur sur téléphone et tablette, sans élargir la page ; les textes longs reviennent à la ligne. Les champs et tableaux du portail client sont contrôlés séparément dans `tests/b2b-portal.spec.js`. Les fixtures n’écrivent pas dans la production.

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

## Textes, photos et informations légales

Les intitulés et marques de produits existants entièrement en majuscules ont été convertis en minuscules dans Coco. Les noms des produits et catégories s’affichent désormais avec une majuscule initiale dans le catalogue public, le portail B2B, la liste Produits et les fiches Coco. Les autres lettres conservent leur casse, sauf les libellés entièrement en majuscules qui sont normalisés. Les références, codes-barres, identifiants et valeurs de catégorie utilisées pour les filtres restent inchangés. Ouvrir puis enregistrer une fiche sans modifier son nom ni sa catégorie conserve les valeurs stockées, même si leur présentation a changé.

459 photographies WebP ont été intégrées dans `products.photo_data`, depuis l’ancien catalogue public de GAMA et des pages publiques de fabricants ou distributeurs, après vérification des correspondances décrites dans les audits. Les 21 photos préexistantes sont conservées : 480 produits actifs sont illustrés. Les correspondances par référence seule ont été écartées lorsque le modèle, la taille ou le produit différaient. [Le registre des sources](audits/data/storefront-product-photo-sources-2026-10-07.json) donne l’URL produit, l’image, les dimensions et son empreinte. Les photos se chargent à la demande avec les contrôles de publication habituels. Un fichier absent ou invalide affiche **Foto por confirmar** ; aucune photo produit générée par IA n’est introduite. Le registre [des photos à compléter](audits/data/storefront-missing-photos-2026-10-07.csv) contient les produits restants, y compris les services sans objet physique.

**Site public → Informations légales** propose raison sociale, RUC de 13 chiffres, contact de confidentialité, information légale, livraison/changements/garanties et cookies/stockage. Les conditions de demande et la confidentialité restent modifiables dans les contenus. L’administration signale les informations manquantes. La raison sociale vérifiée, le RUC et l’adresse de confidentialité sont volontairement laissés à compléter sur demande du propriétaire ; le numéro fiscal de 11 chiffres du paramétrage ERP n’est pas présenté comme un RUC valide. Cette mise à jour ne certifie pas une conformité juridique complète : les coordonnées et les modalités réelles de conservation, transfert et livraison doivent être validées par GAMA.

Le pied de page ouvre chaque texte dans une fenêtre accessible. Le formulaire de devis identifie les champs obligatoires : contact, e-mail, sélection avec quantités valides et consentement non précoché. Entreprise, téléphone et observations sont facultatifs. Les taxes sont indiquées près du prix et détaillées dans la fiche. Le formulaire rappelle la finalité du traitement et l’absence de souscription commerciale ; une demande reste à confirmer par l’équipe avant tout achat.

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

### Images des catégories

Les catégories présentent une photographie réelle d’un produit actif publié disposant d’une photo. Le serveur choisit `photo_id` parmi ces produits ; sans photo vérifiée, la tuile affiche un pictogramme neutre. Les anciennes illustrations de catégories générées par IA ne sont plus publiées par la compilation. Cliquer sur une tuile conserve le filtre du catalogue. Les mêmes photos Coco apparaissent dans la grille, les fiches et la sélection de devis.

### Comptes cloud et Mes documents

**Compte cloud → Créer un compte client pour le site internet** ouvre une recherche des entreprises clientes (nom, jusqu’à 100 résultats). Le choix explicite du client ouvre le même écran d’activation, de création et d’invitation que sa fiche Contacts. Le bouton est également disponible dans **Configuration → Utilisateurs** ; il exige les droits Site web, Utilisateurs et Contacts. Aucun compte ni e-mail n’est créé avant validation de l’invitation.

Dans Contacts, la ligne d’un client actif propose **Compte cloud du client** aux administrateurs disposant de Site web et Utilisateurs. Activer l’accès de l’entreprise, puis créer et inviter un compte ou associer explicitement un compte client existant. La suspension d’une entreprise ou d’une association prend effet sur chaque requête et téléchargement. L’adresse e-mail ne crée aucune association automatique. Plusieurs utilisateurs peuvent appartenir à la même entreprise ; un utilisateur ne peut appartenir qu’à une entreprise. Les profils clients restent inactifs dans l’ERP.

Le portail [gama-coco.pages.dev/b2b.html](https://gama-coco.pages.dev/b2b.html) utilise les prix négociés et le résolveur commun : contrat daté, prix spécifique client, promotion, groupe puis catégorie. Les paliers sont recalculés pour la quantité choisie. Le panier est vérifié à nouveau côté serveur avant création de la demande. La rubrique **Mes documents** rassemble devis diffusés, factures internes ou fiscales et preuves de livraison, par pages de 30 avec recherche et filtre. Chaque téléchargement refait les contrôles d’appartenance ; aucune photo, note privée, coût produit ou adresse Storage n’est exposé par la liste. Un fichier absent est indiqué comme en attente.

L’invitation et la récupération de mot de passe passent par le callback Auth existant de l’ERP, puis reviennent au portail Cloudflare. Le client définit sa propre préférence pour les rappels de factures et les enquêtes. Les deux sont désactivées par défaut. Voir [automatisations](automation.md) pour le paramétrage des envois.

## Portail entreprises B2B

Le lien **Mi empresa** ouvre le portail espagnol, sur mobile et ordinateur. La source canonique est `src/storefront/b2b.html/js/css`. La compilation publie `gama-b2b.html` avec l’ERP GitHub Pages et `b2b.html` dans le paquet Cloudflare. Le bouton d’administration ouvre le portail Cloudflare. Les liens de catalogue de cette page pointent vers le vrai site public, configuré par `catalogue_url` dans `config/storefront-runtime.json`, et non vers l’aperçu réservé aux administrateurs. Le SDK Auth local et le générateur PDF sont chargés à la demande. Le site public conserve son accès anonyme ; seul le portail nécessite une connexion.

Depuis le 5 octobre 2026, l’entrée **Mi empresa** du menu public pointe vers `https://lisciandraj.github.io/Pro-manager-Gama/gama-b2b.html`. Cette navigation vient de la configuration publiée (version 22), modifiable dans **Site web → Identité et apparence** ; son ajout ne nécessite pas de republication Cloudflare. L’icône de compte dans l’en-tête et la page locale `b2b.html` sont également publiées sur Cloudflare depuis le 5 octobre 2026. L’icône ouvre directement `https://gama-coco.pages.dev/b2b.html`, à côté du panier, sur ordinateur et téléphone.

Dans **Site web → Site public → Portal B2B**, l’administrateur active la catégorie d’accès pour chaque entreprise, invite un nouveau compte ou associe explicitement un compte client existant. Les catégories tarifaires A/B/C restent indépendantes. L’invitation présente entreprise, nom, e-mail, objet et message avant l’envoi explicite. L’Edge Function vérifie les droits Site web, Contactos et Utilisateurs avant d’inviter, puis crée une association avec le jeton de l’administrateur. Une invitation envoyée dont l’association échoue demande une vérification manuelle, sans nouvel envoi automatique. Le lien d’invitation utilise la route de définition de mot de passe autorisée de l’ERP, puis ouvre le portail.

Chaque compte voit les prix calculés pour son entreprise, ses sélections favorites, ses demandes, ses factures PDF/XML autorisées ou pièces enregistrées, ses preuves de livraison et son état de compte PDF. Les favoris reconstituent la sélection, puis les prix doivent être revus avant l’envoi. Les factures et preuves utilisent la référence ERP dans leurs titres et fichiers. Les preuves montrent photo, signature et date/GPS lorsqu’ils ont été enregistrés ; elles ne reconstituent pas une position absente.

Une sélection envoyée crée une demande réelle dans Ventes → Demandes clients ; le traitement commercial et le contrôle du crédit interviennent lors de la confirmation du pedido. Les prix, taxes, quantités et adresse sont revalidés côté serveur. La même clé peut être réessayée après une interruption sans dupliquer la demande. L’adresse d’agence choisie est conservée jusqu’au devis puis au TMS.

La sécurité repose sur `b2b_customer_access` et `b2b_memberships`, jamais sur une correspondance d’e-mail. Les profils `cliente` restent inactifs dans l’ERP : ses restrictions de tables, Storage et anciennes RPC ne sont pas rouvertes. Les façades `gama_b2b_action` vérifient connexion réelle, e-mail confirmé, absence de bannissement, MFA si inscrit, entreprise active, catégorie activée et association active à chaque opération. Les téléchargements SRI contrôlent la propriété avant de signer une URL privée de 60 secondes. Une révocation efface les données affichées et la session du portail. Aucun coût d’achat, fournisseur ou document d’une autre entreprise n’est exposé.

Tests isolés : `tests/ec-b2b-management-stock-db.test.cjs`, `tests/identity-admin.test.mjs`, `tests/sri-openapi-edge.test.cjs`. Parcours navigateur : `tests/b2b-portal.spec.js` et `tests/storefront.spec.js`. Les tests n’envoient aucune invitation et ne créent aucune demande réelle en production.

L’icône **Mi empresa** se trouve dans la barre horizontale, immédiatement avant le panier, sur ordinateur et sur téléphone. Elle ouvre la connexion du portail B2B (`/b2b.html`). Son accès reste visible lorsque le bouton de contact est désactivé. La zone tactile mesure au moins 44 px sur téléphone.
