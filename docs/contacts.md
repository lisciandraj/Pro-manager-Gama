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
