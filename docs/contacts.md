# Contacts

Le module rassemble les entreprises clientes, fournisseurs, personnes rattachées aux clients et contacts de prospects. Les personnes du CRM ne sont visibles qu’avec les droits CRM existants. Les données restent dans leurs tables d’origine : aucun doublon n’est créé pour réunir les listes.

- Recherche sur les noms, coordonnées, identification, entreprise et ville ; filtres par type et coordonnées manquantes ; archivage, restauration, affichage en liste/cartes et fusion des entreprises déjà disponibles.
- Les personnes clientes héritent du nom et de la ville de leur entreprise dans la liste. Leur formulaire sélectionne le client parent.
- Téléphones et e-mails sont cliquables. Le formulaire fournisseur permet aussi de modifier province, pays et code postal.
- **Historique** ouvre les documents associés et leurs liens vers ventes, achats, paiements, retours et SAV selon les droits. Les adresses secondaires du client peuvent être ajoutées, modifiées, archivées et restaurées. Les personnes liées peuvent être ouvertes depuis cette fiche.
- Les liens personnels d’un sondage publié sélectionnent ces mêmes clients, fournisseurs et personnes, sans envoi automatique.

Le chargement différé préserve les routes `contacts`, `clients`, `suppliers` et l’API `GamaContacts`. La RPC `gama_contact_person_save` enregistre le changement de contact principal dans une transaction, avec les politiques RLS et contrôles d’actions CRM existants. Un échec ne retire pas le contact principal précédent.

Tests : `contacts.spec.js`, `contacts-people-db.test.cjs`, `contacts-module-db.test.cjs`.

## Unified contact fields

Customer and supplier forms share identity, phone/email and structured address blocks (street, city, province, postal code, country). Customer pricing category/payment terms and supplier contact person remain because sales and purchases use them. Person forms share identity, phone/email and commercial-role blocks; optional LinkedIn is in Additional information. Company addresses appear by reference on linked persons, avoiding a second editable copy. No existing business data is deleted.

CRM prospects have province and postal code; conversion carries the complete address into the customer. New quote/customer selections, manual sales orders and purchase documents use the structured address. Existing accepted document snapshots stay unchanged. Business export includes the added columns.

## Adresses d’agence dans les devis et le TMS

Le devis propose les adresses actives de livraison ou de commande du client sélectionné, depuis **Contacts → Adresses de livraison**. Une adresse de facturation, archivée ou liée à un autre client n'est pas proposée. Le choix remplit le champ de destination ; le commercial peut encore saisir une adresse convenue manuellement. Un changement de client réinitialise ce choix et ignore une ancienne réponse arrivée tardivement. Une erreur de lecture affiche une actualisation sans effacer le texte saisi.

La destination est enregistrée dans l'instantané du devis, puis reprise par le pedido confirmé et les livraisons TMS. Modifier ensuite la fiche d'agence ne modifie pas un document déjà accepté. Le portail B2B propose ces mêmes adresses et conserve l'adresse choisie dans la demande d'origine. Les coordonnées GPS d'un autre lieu ne sont pas réutilisées pour une nouvelle destination.

## Crédit, identification et recouvrement

Le serveur bloque la confirmation d'un pedido si le client a une échéance échue, un dépassement de limite ou un blocage explicite. L'exception administrative reste liée au dossier et à son empreinte : changer ses montants ou le risque client invalide une ancienne autorisation. Le contrôle s'applique aussi aux lignes d'un pedido confirmé. À la création ou au changement, RUC/cédula équatoriens sont contrôlés avec leur chiffre de contrôle et les identifiants normalisés en double sont bloqués.

**Balance por antigüedad** et **Estado de cuenta y recordatorio** utilisent les soldes comptables après paiements, avoirs et retenues. Le texte de relance et le PDF se préparent automatiquement à l'ouverture. L'envoi reste une action de l'utilisateur : partage du PDF lorsqu'il est disponible sur téléphone, ou ouverture de la messagerie/WhatsApp avec téléchargement du PDF à joindre. Aucune relance n'est envoyée en arrière-plan.
## Localisation des adresses et TMS

La migration `contact_address_geocoding` ajoute une file privée et un cache par adresse complète pour les clients, fournisseurs, prospects et sites de livraison disposant des champs GPS. Les coordonnées existantes ne sont pas remplacées. Modifier la rue, la ville, la province, le code postal ou le pays invalide les coordonnées de l’ancienne adresse ; un résultat réseau périmé ne peut pas être appliqué à une nouvelle adresse ni écraser une correction manuelle. L’éditeur Contacts n’envoie plus les champs GPS inchangés, afin de préserver un résultat trouvé après son ouverture. Les fournisseurs disposent aussi des champs latitude/longitude.

Les coordonnées d’un client ou d’un site de livraison sont reprises pour la même destination dans le TMS. Les livraisons en chargement, parties, clôturées, les coordonnées corrigées et les autres destinations sont préservées. Une ville ou une autre adresse ne reçoit jamais par défaut le point du siège. Si plusieurs sites correspondent avec des positions différentes, la destination reste à préciser. Les mises à jour ignorent les lignes momentanément verrouillées ; le contrôle serveur les reprend ensuite sans bloquer l’enregistrement du contact. Le calcul de tournée et la carte locale restent séparés du géocodage.

La recherche externe est **désactivée par défaut** (`private.contact_geocode_settings.enabled=false`) et exige l’autorisation de transmettre les composantes de l’adresse à Photon. Les données envoyées sont uniquement rue/numéro, ville, province, code postal et code pays ; aucun nom, téléphone, e-mail, identifiant fiscal ou document. Le service est [Photon](https://github.com/komoot/photon), données © OpenStreetMap contributors, avec un plafond initial de 200 requêtes/jour, une seule requête simultanée, un délai minimal de deux secondes et trois tentatives espacées en cas d’indisponibilité. Ses [conditions d’utilisation](https://photon.komoot.io/) permettent un usage raisonnable sans garantie de disponibilité. Aucun compte ou clé payante n’est créé.

Un résultat est enregistré automatiquement uniquement si la géométrie est un point valide et si la rue, le numéro, la ville ou le code postal et le pays correspondent. Les centres de rues/villes, résultats ambigus et adresses absentes restent à vérifier. Les tableaux, fonctions et réponses de la file ne sont pas exposés aux clients. `cron` traite les réponses sans ouvrir l’ERP ; l’arrêt du service empêche aussi l’application d’une réponse encore en attente. Les tests `contact-address-geocoding-db` utilisent des réponses simulées dans une base isolée et couvrent exactitude, ambiguïté, cache, changements d’adresse, corrections manuelles, TMS, permissions, plafonds et reprises.

## Création sans doublons et historique transversal

Pendant la création, Contacts signale les fiches autorisées du même type dont
l’identifiant, le courriel, le nom exact normalisé ou le téléphone concorde. Le
bouton **Utiliser la fiche existante** ouvre son éditeur au lieu de créer une
seconde fiche. Un nom identique reste une suggestion : les homonymes légitimes
ne sont pas bloqués. Les contrôles serveur d’identification restent en place.
La recherche utilise les données déjà chargées pour l’éditeur, sans lecture
supplémentaire ni stockage local des coordonnées ; elle n’effectue aucune fusion.

Dans le dossier d’un client ou fournisseur, **Historique client ou fournisseur**
réunit les documents commerciaux accessibles, les activités CRM et les fichiers
liés, triés du plus récent au plus ancien. Les activités et fichiers sont limités
aux 100 derniers de chaque source. Les RPC, RLS et droits d’origine filtrent les
lectures ; le regroupement n’accorde aucun droit financier ou documentaire.
Chaque ligne ouvre son document ou les activités du même dossier. Les onglets
spécialisés et les états de compte existants restent disponibles.

Validation : `tests/simplified-sales-contacts.spec.js` couvre les suggestions,
leur retrait, la réutilisation, l’ordre chronologique et la fermeture à la
fin de session.

## Champs Contacts Odoo

Les formulaires de création et de modification reprennent les champs standard de la fiche Contacts Odoo 18 : particulier/société, civilité, nom, société liée pour un interlocuteur, poste, téléphone, mobile, second téléphone Coco, e-mail, site web, langue, identification fiscale, étiquettes, adresse structurée avec complément, référence interne, immatriculation de société, photo/logo par URL et commercial responsable. Les adresses de facturation/livraison, le secteur, les notes internes, l’archivage et les conditions commerciales déjà présents restent accessibles dans le dossier. Les conditions de paiement et tarifs gardent leurs moteurs Coco existants.

Le mobile est distinct du second téléphone. Les nouveaux champs sont conservés dans le profil de l’identité partagée ; une personne liée garde son propre profil. La sauvegarde `coco_contact_save` accepte un objet facultatif `p_data.odoo`, dans la même transaction et sous la même version que les coordonnées. Les champs absents restent inchangés ; une valeur `null` efface un champ facultatif. La liste des commerciaux vient de l’équipe CRM autorisée ; sans accès CRM, l’attribution existante est préservée. Les erreurs et conflits conservent le brouillon. Les photos sont des liens d’images HTTP(S), affichés sans en-tête de provenance ; aucun fichier n’est téléversé par ce champ.

Le complément d’adresse est affiché dans le dossier et hérité par les interlocuteurs. Il ne réécrit pas les instantanés commerciaux ni les destinations TMS. Les champs propres aux extensions Odoo (multi-sociétés, comptes bancaires/comptables, position fiscale et formats de facturation) ne créent pas de seconde configuration comptable dans Contacts.

Référence : [formulaire Contacts Odoo 18](https://github.com/odoo/odoo/blob/18.0/odoo/addons/base/views/res_partner_views.xml). Contrôles dédiés : `tests/contact-odoo-fields.test.cjs` pour les transactions et droits, `tests/contact-odoo-fields.spec.js` pour les formulaires et le dossier en français, sur téléphone et ordinateur.

La migration Contacts Odoo a été installée en production le 7 novembre 2026, version `20261107191036`. Le SQL du dépôt est identique aux octets enregistrés dans le registre Supabase (SHA-256 `4f5986be6d465ab310bb4aff6a26cdf03197757791799f31adfd067961d92d67`). Les colonnes, façades invocateur, droits et déclencheurs d’historique ont été vérifiés après installation ; aucun contact métier de test n’a été créé en production. La publication de l’interface reste contrôlée séparément par le workflow Pages.

## Fiches individuelles et entreprises

Le **type de fiche** (Individuel / Entreprise) est distinct du **rôle commercial**
(client, fournisseur ou interlocuteur CRM). La liste affiche ces deux dimensions
et permet de filtrer le type indépendamment du rôle. Une ancienne fiche dont le
type n’a pas été renseigné reste « Non défini » jusqu’à un choix explicite.

Une fiche individuelle client ou fournisseur peut rester autonome ou sélectionner
une **Entreprise liée**, cliente ou fournisseur, active et accessible. Ce lien est
facultatif et modifiable ; les coordonnées et l’adresse de la personne restent
propres à sa fiche. Il ne fusionne pas les identités. La synthèse permet d’ouvrir
l’entreprise et son onglet **Interlocuteurs et adresses** réunit aussi les personnes
rattachées par cette relation. Les interlocuteurs CRM conservent leur parent client
ou prospect et leur mécanisme existant d’héritage d’adresse.

La migration additive `20261108154619_contacts_individual_company_links.sql`
expose le type et les liens dans le répertoire et le dossier. La sauvegarde
versionnée accepte `p_data.odoo.parent_id` (identifiant de profil ou `null` pour
détacher) dans la transaction de la fiche ; seuls les individus clients et
fournisseurs utilisent ce champ. Le serveur refuse une entreprise parente
inaccessible, archivée ou de type individuel, les boucles et la reclassification
d’une entreprise qui possède encore des individus rattachés. Les droits de chaque
rôle et l’historique des changements restent appliqués. Aucun contact existant
n’est reclassé par la migration.

Validation isolée : `contact-nature-company.test.cjs` pour les transactions,
permissions et relations ; `contact-nature-company.spec.js` pour la création,
les filtres, la conservation des brouillons et la navigation entre les fiches
sur ordinateur et téléphone. La migration et l’interface doivent toutes deux
être publiées avant l’utilisation de ces nouveaux liens en production.

La migration de rattachement a été installée sur le **développement**
(`mknsaibrewksgomuslev`) le 8 novembre 2026, sous la version serveur
`20261108163417`. Ses octets correspondent à la source
`20261108154619_contacts_individual_company_links.sql` (SHA-256
`88ea8d3a675a68ecb9a1dc2bec1ed3e4bb8e73256f31706476ea1e8682ee6ad1`).
Les fonctions invocateur, droits, index et déclencheur ont été vérifiés, sans
création de contact métier. La production indépendante
(`vhutzdfatijjpahsqkne`) ne dispose pas encore des fonctions Contacts Odoo
requises ; ce lot n’y a pas été appliqué. La publication des environnements
reste subordonnée à leur contrôle public de disponibilité.
