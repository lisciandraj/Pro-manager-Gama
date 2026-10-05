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
