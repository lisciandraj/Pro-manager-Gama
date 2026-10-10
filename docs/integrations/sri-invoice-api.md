# Factures Coco → fournisseur SRI par API

Préparation ajoutée le 10 octobre 2026. Le contrat `coco.sri.invoice.v1` est
indépendant du fournisseur. Il ne s'agit pas du JSON natif de RUXI, Datil ou d'un
autre prestataire : leur adaptateur reste à développer à partir de leur documentation
et d'un compte de test. Aucun endpoint ni paramètre fournisseur n'est supposé.

## Utilisation dans Coco

Facturation SRI → choisir la forme de paiement → **Vérifier les données API**.
Le diagnostic fonctionne même si le moteur fiscal est désactivé. Il affiche les
données absentes ou incohérentes et permet de télécharger le JSON lorsqu'elles
sont complètes. Cette lecture ne réserve aucun numéro, ne crée aucun dossier et
n'émet aucune facture. Un dossier déjà préparé est relu depuis son instantané fiscal.

La préparation SRI habituelle conserve maintenant le client, son identification,
son adresse, son e-mail et les lignes de l'instantané de la facture interne. Elle
ne relit plus les prix et identités dans des fiches modifiables. Les données
historiques manquantes doivent faire l'objet d'une correction explicite et auditée ;
elles ne sont pas inventées ni reprises silencieusement d'une fiche actuelle.

## Endpoint authentifié, lecture seule

`POST /functions/v1/gama-sri`, JWT utilisateur et clé publique Supabase habituels :

```json
{"action":"invoice_preview","id":"UUID_DE_LA_FACTURE_INTERNE","payment_code":"20"}
```

L'administrateur actif doit avoir accès à Comptabilité et le droit d'export ; les
lectures utilisent le JWT du demandeur et les RLS. Le corps client ne peut fournir
ni montant, ni statut autorisé, ni instantané de remplacement. Aucune clé prestataire
ou certificat n'est accepté par cette action.

La réponse contient `valid`, `errors[]` (`field`, `code`), `warnings[]`,
`mode` (`preview` ou `frozen`), `issue_id`, `status`, `can_prepare`,
`requires_provider_adapter: true`, `emission_enabled: false`, `payload_sha256`,
`idempotency_key` et `payload`. Le booléen `valid` indique la cohérence structurelle
dans le périmètre ci-dessous, jamais une autorisation SRI ni une validation des
taux applicables à l'opération. L'empreinte SHA-256 porte sur le JSON compact du
payload généré, dans l'ordre des propriétés du sérialiseur Coco, sans signature.
Une prévisualisation peut changer avant préparation ; elle n'a pas de clé idempotente.

[Exemple JSON fictif](sri-invoice-api.example.json) pour préparer le mapping fournisseur.

## Correspondance des données

| Bloc JSON | Source figée / destination |
| --- | --- |
| `source` | UUID et numéro interne, commande et devis ; même registre financier |
| `document` | Code `01`, date, échéance, USD, environnement, établissement, point, séquence et code numérique |
| `issuer` | RUC, raison sociale, nom commercial, adresses, obligation comptable, RUC du fournisseur logiciel |
| `buyer` | Type `04` RUC / `05` cédula, identification, nom, adresse et e-mail de la facture |
| `lines` | Identifiants, référence, désignation, quantité, prix net, base et TVA par ligne |
| `tax_totals` | Bases et TVA groupées par code SRI, y compris le taux zéro |
| `totals` | Sous-total, remise fiscale, TVA, pourboire et total cohérents avec le registre |
| `payments` | Moyen SRI confirmé, montant et délai en jours issu de l'échéance |
| `additional_information` | Champ exact `RUC Proveedor` |

Les montants sont des **chaînes décimales**, arrondies au centime par ligne en
HALF_UP. Quantités et prix unitaires conservent six décimales. Le total des paiements
est le total facturé, et non le solde restant après encaissements.

`pricing_basis = net_unit_price` : les prix du registre intègrent déjà les remises.
Le montant fiscal `discount` est donc `0.00`, pour éviter toute double déduction.
`lines[].commercial` conserve le prix catalogue et le pourcentage commercial à titre
de traçabilité, sans les soustraire à nouveau. Un prestataire exigeant des prix
bruts et remises séparées doit prouver que sa conversion conserve chaque base et total.

Le périmètre initial est celui des factures nationales ordinaires de l'existant :
RUC/cédula, USD, IVA 0/5/12/13/14/15 et paiements 01/16/19/20. Les codes de TVA ne
prouvent pas qu'un taux est applicable à une date ou à un produit. Le taux zéro
ne représente pas automatiquement une exonération ni une opération non assujettie.
Consommateur final, passeport, ICE, RIMPE et cas particuliers demandent un contrat
étendu et des validations dédiées ; aucune compatibilité complète n'est annoncée.

## Raccordement du prestataire

1. Valider son contrat API, son environnement de test, ses mécanismes de recherche
   et ses exigences d'identification du fournisseur logiciel.
2. Écrire un adaptateur serveur depuis ce contrat ; garder secrets et certificat
   chez le serveur ou le prestataire selon son modèle. Ne jamais mettre une clé
   privée dans l'interface ou le JSON téléchargeable.
3. Conserver **un seul propriétaire de la numérotation**. Le contrat actuel indique
   `numbering_owner: coco` et réutilise la séquence réservée par `gama_sri_prepare`.
   Si le prestataire impose sa propre séquence, il faut un mode dédié avant l'envoi ;
   on ne lui transmet pas en parallèle une nouvelle série Coco.
4. Figer le dossier puis utiliser `coco:sri:01:<environment>:<issue UUID>` comme clé
   de dédoublonnage. La clé seule ne rend pas un prestataire idempotent : son API
   doit la supporter, sinon la passerelle doit gérer revendication et recherche.
5. Persister fournisseur, identifiant distant, empreinte, statut distant et événements
   dans le suivi serveur. Une réponse à l'envoi vaut réception/traitement, pas autorisation.
   Une coupure après POST exige une consultation du même dossier, sans nouvelle facture.
6. Vérifier l'autorisation, la clé et le XML retournés contre l'instantané. Archiver
   XML et RIDE dans `sri-documents` privé, puis enrichir **la même** facture interne.
   Aucun second chiffre d'affaires, paiement ou mouvement de stock n'est créé.
7. Si le fournisseur propose des webhooks, ajouter vérification de signature,
   protection anti-rejeu et traitement idempotent avant de les activer. Aucun webhook
   générique non authentifié n'est créé par cette préparation.

Le flux existant Open API / signataire privé reste en place. Cette livraison ne
branche pas un nouveau fournisseur et n'active aucune émission réelle. Les
instantanés fiscaux existants ne sont ni régénérés ni modifiés ; un trigger protège
leur contenu et leur identité tout en autorisant les mises à jour de suivi serveur.

## Validation et sources

Tests isolés : arrondis, TVA mixte, remises nettes, échéances, erreurs de total,
instantanés, droits/MFA/RLS existants, appels concurrents d'émission et absence
réelle d'appel externe pendant le diagnostic. La compilation de l'interface est
nécessaire ; la fonction Edge et la migration se déploient séparément du site.
Aucun test ne transmet de facture réelle au SRI.

Références contrôlées : [SRI, fiche technique 2.34 et schémas XML](https://www.sri.gob.ec/facturacion-electronica),
[secrets Edge Functions](https://supabase.com/docs/guides/functions/secrets).
Voir aussi [module SRI](../modules/sri.md) et [installation Open API](../../services/sri/OPENAPI.md).

Déploiement serveur vérifié le 10 octobre 2026 : migration `20261010170822`
et Edge Function `gama-sri` version 6, JWT activé. Aucun dossier fiscal créé
pendant cette installation. La publication web se vérifie séparément via le
workflow Pages et le commit de `coco-build.json`.
