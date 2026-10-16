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

Le devis propose les adresses actives de livraison ou de commande du client sélectionné, depuis **Contacts → Historique → Adresses secondaires**. Une adresse de facturation, archivée ou liée à un autre client n'est pas proposée. Le choix remplit le champ de destination ; le commercial peut encore saisir une adresse convenue manuellement. Un changement de client réinitialise ce choix et ignore une ancienne réponse arrivée tardivement. Une erreur de lecture affiche une actualisation sans effacer le texte saisi.

La destination est enregistrée dans l'instantané du devis, puis reprise par le pedido confirmé et les livraisons TMS. Modifier ensuite la fiche d'agence ne modifie pas un document déjà accepté. Le portail B2B propose ces mêmes adresses et conserve l'adresse choisie dans la demande d'origine. Les coordonnées GPS d'un autre lieu ne sont pas réutilisées pour une nouvelle destination.

## Crédit, identification et recouvrement

Le serveur bloque la confirmation d'un pedido si le client a une échéance échue, un dépassement de limite ou un blocage explicite. L'exception administrative reste liée au dossier et à son empreinte : changer ses montants ou le risque client invalide une ancienne autorisation. Le contrôle s'applique aussi aux lignes d'un pedido confirmé. À la création ou au changement, RUC/cédula équatoriens sont contrôlés avec leur chiffre de contrôle et les identifiants normalisés en double sont bloqués.

**Balance por antigüedad** et **Estado de cuenta y recordatorio** utilisent les soldes comptables après paiements, avoirs et retenues. Le texte de relance et le PDF se préparent automatiquement à l'ouverture. L'envoi reste une action de l'utilisateur : partage du PDF lorsqu'il est disponible sur téléphone, ou ouverture de la messagerie/WhatsApp avec téléchargement du PDF à joindre. Aucune relance n'est envoyée en arrière-plan.
## Localisation des adresses et TMS

La migration `contact_address_geocoding` ajoute une file privée et un cache par adresse complète pour les clients, fournisseurs, prospects et sites de livraison disposant des champs GPS. Les coordonnées existantes ne sont pas remplacées. Modifier la rue, la ville, la province, le code postal ou le pays invalide les coordonnées de l’ancienne adresse ; un résultat réseau périmé ne peut pas être appliqué à une nouvelle adresse ni écraser une correction manuelle. L’éditeur Contacts n’envoie plus les champs GPS inchangés, afin de préserver un résultat trouvé après son ouverture. Les fournisseurs disposent aussi des champs latitude/longitude.

Les coordonnées d’un client ou d’un site de livraison sont reprises pour la même destination dans le TMS. Les livraisons en chargement, parties, clôturées, les coordonnées corrigées et les autres destinations sont préservées. Une ville ou une autre adresse ne reçoit jamais par défaut le point du siège. Si plusieurs sites correspondent avec des positions différentes, la destination reste à préciser. Les mises à jour ignorent les lignes momentanément verrouillées ; le contrôle serveur les reprend ensuite sans bloquer l’enregistrement du contact. Le calcul de tournée et la carte locale restent séparés du géocodage.

La recherche externe est **désactivée par défaut** (`private.contact_geocode_settings.enabled=false`) et exige l’autorisation de transmettre les composantes de l’adresse à Photon. Les données envoyées sont uniquement rue/numéro, ville, province, code postal et code pays ; aucun nom, téléphone, e-mail, identifiant fiscal ou document. Le service est [Photon](https://github.com/komoot/photon), données © OpenStreetMap contributors, avec un plafond initial de 200 requêtes/jour, une seule requête simultanée, un délai minimal de deux secondes et trois tentatives espacées en cas d’indisponibilité. Ses [conditions d’utilisation](https://photon.komoot.io/) permettent un usage raisonnable sans garantie de disponibilité. Aucun compte ou clé payante n’est créé.

Un résultat est enregistré automatiquement uniquement si la géométrie est un point valide et si la rue, le numéro, la ville ou le code postal et le pays correspondent. Les centres de rues/villes, résultats ambigus et adresses absentes restent à vérifier. Les tableaux, fonctions et réponses de la file ne sont pas exposés aux clients. `cron` traite les réponses sans ouvrir l’ERP ; l’arrêt du service empêche aussi l’application d’une réponse encore en attente. Les tests `contact-address-geocoding-db` utilisent des réponses simulées dans une base isolée et couvrent exactitude, ambiguïté, cache, changements d’adresse, corrections manuelles, TMS, permissions, plafonds et reprises.
