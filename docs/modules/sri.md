# Facturación SRI — module Coco et connecteur Open API

Le menu Administration contient désormais **Facturación SRI** (`sri`). Il utilise
les factures internes existantes, avec accès depuis leur fiche et le suivi des
paiements. L'onglet Comptabilité → SRI reste disponible. Les factures sont paginées,
recherchables par numéro et liées au même dossier commercial et aux mêmes paiements.
Le rendu fiscal ne crée aucun mouvement supplémentaire de stock ou de trésorerie.

Le nouveau fournisseur `openapi` utilise le service privé Python comme passerelle
vers **Open API Facturación SRI**. Les droits et l'archivage existants sont conservés.
Le code de connexion n'héberge pas à lui seul le moteur NestJS, son stockage de
certificats ni son générateur PDF. L'émission réelle reste conditionnée à leur
configuration et aux essais fiscaux, et n'est pas activée par une publication web.

**Périmètre livré : factures nationales ordinaires (01).** Les avoirs, retenues et
guías de remisión du projet amont ne sont pas encore raccordés aux modules Coco.
Ils ne sont pas présentés comme fonctionnels.

Voir [installation, contrat API et limites de reprise](../../services/sri/OPENAPI.md)
et [configuration privée d'exemple](../../services/sri/openapi.env.example).
Aucune nouvelle table n'est nécessaire : le fournisseur est mémorisé dans le reçu
JSON serveur de chaque émission. Les documents déjà envoyés par le signataire
historique continuent à utiliser leur traitement historique.

---

## Contrat historique conservé

> État relu le 30 septembre 2026. Les contrats techniques ci-dessous restent rattachés aux modules actuels ; les commandes de validation et la cartographie des sources sont centralisées dans la documentation de développement.

# Facturación SRI — integration status

The Accounting module now has a SRI section. It creates one fiscal issue from an accepted, confirmed internal invoice, preserves its original line and customer snapshot, and assigns a separate nine-digit tax sequence. The invoice remains a management invoice until the SRI authorization is verified.

The workflow is: configure company and establishment → choose payment means → prepare → sign `.p12` on the private worker → submit to the SRI reception SOAP endpoint → query the authorization endpoint by the same 49-digit key → archive signed/authorized XML and RIDE in a private bucket → link the verified authorization to the commercial invoice → email XML and PDF to the customer. No signing key is accepted in the browser.

The signer deliberately supports only ordinary Ecuadorian domestic invoices with numeric cédula/RUC customer identity, payment code 01/16/19/20, and supported VAT rates. It rejects unsupported tax rates and mismatched totals. Credit/debit notes, withholding, delivery notes, RIMPE, ICE, exports and specialized regimes need their own SRI models. These are not silently converted into ordinary invoices.

## Deployment prerequisites

1. Apply `20260927213000_sri_invoice_workflow.sql` to a development database first. Verify its RLS policies and check the existing invoice and accounting flows.
2. Host `services/sri` privately behind HTTPS. Install the pinned `requirements.txt` into its own environment. Provision `SRI_P12_BASE64`, `SRI_P12_PASSWORD`, `SRI_ISSUER_RUC`, `SRI_WORKER_SECRET` and SMTP environment variables on the server. Restrict inbound traffic to the Edge Function if infrastructure permits.
3. Set the matching `SRI_WORKER_URL` and `SRI_WORKER_SECRET` in Supabase Edge secrets, then deploy `gama-sri` with JWT verification on. The service-role key exists only in Edge secrets. The authenticated `status` action reports readiness to the interface; issuance controls remain disabled by default. Set `SRI_EMISSION_ENABLED=true` only when the private signer is configured and ready for supervised SRI tests in `pruebas`.
4. Configure the company's Ecuadorian legal identity in Coco; enter the establishment, emission point and registered software provider's RUC in the SRI tab. Run SRI certification tests in `pruebas` with representative real tax cases and the official invoice XSD. Confirm the signed XAdES-BES document, RIDE and email with the SRI responses.
5. Only after successful certification and provider registration, explicitly enable `SRI_PRODUCTION_ENABLED=true` on the isolated signer instance and select `produccion` in Coco. An actual production SRI document has tax consequences.

The SRI technical sheet v2.34 (July 2026), including its annex 26 provider field, is the primary specification: https://www.sri.gob.ec/web/intersri/facturacion-electronica . Somatech's LGPL-3.0 Odoo repository was used only to study workflow and the key layout; its code is not bundled or loaded into Coco. This component still needs live certification against SRI's test service. No certificate, provider identity, or live SRI credentials are committed.

When reception times out after transmission, do not issue a new key or send blindly again. Use **Consultar SRI**; retain the same signed XML and sequence for recovery. Email transport can time out after a successful delivery; verify with the mail provider before clicking **Enviar al cliente** again.


## Sélection des factures et configuration (1er octobre 2026)

La tuile Administration → Facturation SRI ouvre par défaut les factures internes
non envoyées : absence de référence fiscale externe et absence de dossier SRI,
ou dossier encore en brouillon. La vue `sri_invoice_selection` filtre avant
pagination et conserve les RLS existantes (`security_invoker=true`). Le filtre
Toutes les factures donne accès au suivi historique. Sélection de page, préparation
et envoi groupé sont disponibles selon les droits. Un envoi groupé concerne uniquement
`pruebas`, demande une confirmation du nombre sélectionné et s’arrête après un rejet,
une réponse incertaine ou une erreur. Une facture en traitement n’est pas réémise.
Les séries SRI réservées restent indépendantes du numéro FAC interne.

Depuis la reprise du 2 octobre, une réponse `processing`, `signed` ou `received`
sans demande de revue est suivie d'une seule consultation du même dossier. Le lot
continue uniquement après autorisation vérifiée ; une attente, un rejet ou une
réponse incertaine l'arrête. Aucun nouvel envoi ne sert de consultation. Un rejet
reste consultable sans retour en brouillon ; une consultation encore en attente
n'efface pas le rejet existant.

Le nom XML du champ fournisseur est exactement **RUC Proveedor**, conformément
à l'annexe 26 de la fiche SRI 2.34 (page 135), dans le moteur privé et le DTO Open
API. Les fichiers déjà signés restent immuables. Le diagnostic distingue paramètres
de connexion, moteur inaccessible, configuration incomplète, fournisseur différent,
émission désactivée et droit de validation absent. Il ne valide pas le XML, la
signature, le RIDE ni l'autorisation fiscale.

Configuration → Facturation SRI partage l’identité légale de la fiche entreprise
(RUC, raison sociale, adresse et e-mail), accessible sans quitter la configuration.
Le profil enregistre établissement, point d’émission, RUC du fournisseur logiciel,
nom commercial, adresse d’établissement et obligation comptable. Ces champs sont
figés dans l’instantané à la préparation. Aucun certificat ou secret serveur n’est
exposé au navigateur. Production reste indisponible dans ce nouvel écran de test.
Les RPC de configuration vérifient administrateur actif, droits et MFA existants.

Le déploiement coordonné est décrit dans
[services/sri/deploy/README.md](../../services/sri/deploy/README.md).
La recette comprend les composants persistants mais requiert un serveur privé,
HTTPS, les identifiants et un certificat réel. Elle n’indique pas que le service
est hébergé. Le RIDE Carbone HTML utilise des fonctions annoncées Community ;
le rendu PDF réel et les essais SRI doivent encore être validés sur l’image choisie.

Voir [état vérifié et étapes restantes au 2 octobre](../audits/2026-10-02-sri-recovery.md).

## Documents complémentaires (octobre 2026)

`gama_sri_documents` prépare les codes 03, 04, 06 et 07 à partir de sources métier existantes. Les états et archives sont séparés dans `sri_document_issues`, avec une séquence atomique par type et par série. Le dossier SRI présente un tableau paginé par famille, les références ERP et fiscales, la consultation de la même clé et les téléchargements privés. Voir [les capacités du signataire](../../services/sri/README.md).

Dans Retours, **Reponer y preparar nota de crédito SRI** exige la réception et une confirmation d'inspection. La transaction libère la quarantaine, remet le stock, crée l'avoir et son brouillon 04 ensemble ; un échec fiscal de préparation annule toute la transaction. Elle ne considère pas une émission ou une autorisation externe comme accomplie. Le original doit être une facture réellement autorisée, y compris les factures internes dont le statut fiscal externe est suivi dans leur dossier SRI.

Pour les achats, une facture comptabilisée est mise en file uniquement si l'entreprise est confirmée agente de retención. L'enregistrement de ses métadonnées fiscales vérifiées prépare automatiquement le brouillon 07 si la politique datée du fournisseur est complète. Les erreurs de revue restent visibles sans perdre la facture. Après autorisation, le certificat solde son montant dans le mécanisme comptable de retenues existant, une seule fois. Les pourcentages et comptes se révisent dans le dossier SRI.

Chaque carte de tournée permet de préparer la guía 06 ; l'écran chauffeur ouvre seulement la guía autorisée de sa propre tournée. Les balises dépôt ne sont pas des destinataires. Le brouillon peut être écarté avant envoi pour ajuster la tournée. Après revendication, les arrêts, dates, chauffeur, véhicule et marchandises sont protégés. L'autorisation exige toujours le service privé, son certificat ou le fournisseur fiscal configuré et les essais SRI.
