# Architect ERP — chantier de simplification (septembre 2026)

Moins de modules, moins de clics, les mêmes données. Rien n'a été copié ni
renuméroté : les tables restent celles d'avant ; ce sont les écrans qui se
regroupent. Un ancien identifiant de module reste un **alias** du module qui
l'a absorbé : un lien, un favori ou un droit enregistré sous l'ancien nom
ouvre le bon écran, et côté serveur `private.erp_module_parent()` applique
l'interrupteur du nouveau module aux contrôles qui nomment encore l'ancien.

| Avant | Après | Alias |
|---|---|---|
| Suivi commercial et logistique | **Tableau de bord → Priorités du jour** | `operations` → `dashboard` |
| Suivi de dossier | **Suivi de processus** (PDV / PDC) | — |
| Devis et facture + Commandes clients (+ Factures et encaissements) | **Devis et facture** en 4 onglets | tuiles masquées, identifiants conservés |
| Retours | **Retours** en deux processus, PRC et PRP | — |
| Préparation de commandes + Livraisons / TMS | **Livraison** (Entrega), onglet Préparation en tête | `order-preparation` → `tms` |
| Clients + Fournisseurs | **Contacts** (+ contacts de prospects) | `clients`, `suppliers` → `contacts` |
| Inventaire | retiré : **Entrepôts et stocks → Existences** le couvre | `stock` → `warehouses` |
| Piste d'audit | actions importantes seulement, tuile en haut | — |
| E-mail d'invitation | personnalisable | — |

## 1. Priorités du jour

Les alertes de l'ancien suivi commercial et logistique arrivent dans le
tableau de bord, calculées par le serveur (`gama_dashboard_priorities`) avec
de vraies dates : **rouge** quand la date ou la limite est dépassée, **orange**
quand l'échéance tombe dans la semaine. Les rapprochements bancaires et les
dépenses sans justificatif sont regroupés pour ne pas noyer le reste.

## 2 et 3. Processus numérotés

Chaque processus a un numéro unique que portent tous ses documents :
`PDV-` (vente), `PDC-` (achat), `PRC-` (retour client), `PRP-` (retour
fournisseur) suivi des 8 chiffres du dossier. Les étapes se suivent dans
**Suivi de processus** (onglets PDV et PDC) et dans **Retours** (onglets PRC et
PRP). Détails : [DOCUMENT_REFERENCES.md](DOCUMENT_REFERENCES.md),
[RETURNS.md](RETURNS.md).

## 4. Devis et facture

Un seul module, quatre onglets qui suivent le processus de vente :
**Demandes clients · Devis · Commandes · Factures**. Chaque onglet est l'écran
qui existait déjà (demandes, devis, commandes clients, factures et
encaissements) et n'apparaît qu'avec son droit. La liste des devis ne montre
plus les factures sous chaque devis : elles sont dans l'onglet Factures, et
chaque commande garde ses factures dans sa fiche. Les tuiles « Commandes
clients » et « Factures et encaissements » disparaissent du menu pour qui voit
Devis et facture ; le magasinier, qui n'a que les commandes, garde sa tuile
Commandes clients, sans onglets. Les identifiants `sales-orders` et
`payments` restent des droits à part entière (un profil peut toujours ne pas
voir les factures) et leurs anciens liens ouvrent leur onglet.

## 5. Livraison

Un seul module, cinq onglets : **Préparation**, Planification, Sortie des
colis, Preuve de livraison, Historique. Préparer, c'est scanner : les
quantités sont déjà prévues, le premier scan démarre la préparation, chaque
lecture valide sa ligne et, au dernier produit, le colis est créé et la
commande passe **« Prête à expédier »**. Une expédition partielle ouvre
directement la clôture pour en donner le motif. Détails :
[FULFILLMENT_P1.md](FULFILLMENT_P1.md).

## 6. Contacts

Trois onglets — Clients, Fournisseurs, Contacts de prospects — et un seul
**« ＋ Nouveau contact »** qui demande d'abord de quel type de contact il s'agit
et ouvre le bon formulaire. Chaque onglet est l'écran qui existait déjà ; le
CRM garde aussi sa propre liste de contacts. Un profil qui n'avait pas accès
aux clients ou aux fournisseurs n'a pas accès à Contacts : la fusion n'ouvre
aucun droit.

## 7. Inventaire retiré

La liste de l'Inventaire répétait l'onglet **Existences** d'Entrepôts et
stocks, qui montre en plus l'entrepôt, le réservé, l'entrant et la valeur.
La recherche d'Existences trouve maintenant aussi par code-barres.

## 8. Piste d'audit

`gama_audit_trail` renvoie seulement les actions importantes, en mots métier,
avec qui et quand : mouvements de stock, encaissements, paiements et
remboursements, factures, validations, écritures comptabilisées, changements
d'accès. Filtres par type, texte, dates et personne ; 50 lignes par page ;
export CSV. La tuile du module est la première chose de l'écran. Le journal
technique ligne à ligne (`erp_audit_events`, `gama_audit`) reste en base.

## 9. E-mail de création d'accès

**Utilisateurs → E-mail d'invitation** : objet et message, avec `{nombre}`,
`{empresa}`, `{rol}`, `{correo}` et un aperçu. À chaque invitation, l'e-mail
est visible et modifiable pour la personne invitée. Un réglage unique du
modèle « Invite user » dans Supabase est nécessaire pour qu'il s'affiche :
voir [supabase/README.md](supabase/README.md).

## Base de données

Migrations appliquées en production, dans l'ordre : `dashboard_priorities`,
`dashboard_priorities_groups`, `purchase_process_number`,
`return_process_number`, `delivery_module`, `contacts_module`, `audit_trail`,
`invitation_template`. Tests PGlite : `tests/*-db.test.cjs`.
