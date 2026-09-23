# Modèles de localisation de l'entreprise

Ces fichiers constituent les modèles proposés lors du premier enregistrement de l'entreprise dans **Configuration → Votre entreprise**. Un modèle ajoute le plan comptable national, les taux de TVA courants et les six comptes utilisés par les écritures automatiques. Il ne crée pas une nouvelle base Supabase.

| Pays | Plan | Comptes | Devise proposée | TVA proposée |
|---|---|---:|---|---|
| Équateur | NIIF | 501 | USD | 15 %, 5 %, 0 % |
| France | PCG | 656 | EUR | 20 %, 10 %, 5,5 %, 2,1 %, 0 % |
| Belgique | PCMN | 426 | EUR | 21 %, 12 %, 6 %, 0 % |

Il s'agit de modèles de départ datés du 19 septembre 2026, issus des localisations Odoo 19.0, avec un sous-ensemble des taux courants. Ils n'appliquent pas automatiquement un régime fiscal aux produits. Les taxes spéciales, exonérations, opérations intracommunautaires, déclarations et obligations de facturation électronique ne sont pas implémentées par cette installation. Les taux et comptes peuvent être adaptés dans Comptabilité. Les autres pays restent configurables manuellement.

L'installation est atomique, réservée aux administrateurs actifs et autorisée uniquement avant la première écriture comptable. Elle conserve les comptes et taxes existants. Un nouveau compte dont le numéro est occupé reçoit un préfixe pays ; les correspondances internes utilisent son identifiant. Une répétition du même modèle ne crée pas de doublons. Le pays est verrouillé après installation. Aucun modèle n'est installé par la migration de déploiement.

## Origine et licence

Données des comptes adaptées des fichiers officiels Odoo `addons/<localisation>/data/template/account.account-<pays>.csv` :

- [Équateur](https://github.com/odoo/odoo/tree/19.0/addons/l10n_ec)
- [France](https://github.com/odoo/odoo/tree/19.0/addons/l10n_fr_account)
- [Belgique](https://github.com/odoo/odoo/tree/19.0/addons/l10n_be)

Les noms, codes et états actifs sont repris. Les types Odoo sont ramenés aux cinq types du moteur comptable Architect. Les mappings automatiques et le format JSON sont des adaptations Architect. Chaque fichier conserve l'URL source et le SHA-256 du CSV d'origine. Les données adaptées restent sous LGPL-3.0 ; voir `LICENSE.odoo` et `COPYRIGHT`.

Références fiscales complémentaires : [SRI — IVA](https://www.sri.gob.ec/impuesto-al-valor-agregado-iva), [Ministère français de l'Économie — TVA](https://www.economie.gouv.fr/particuliers/tva-taux-quotidien). La liste proposée ne constitue pas un moteur de détermination fiscale.

Pour actualiser les données, modifier les JSON puis exécuter `python scripts/build-company-localizations.py`. Le script reconstruit la section de données de la migration initiale. Pour une installation déjà déployée, créer une nouvelle migration versionnée ; ne pas rejouer la migration initiale ni modifier les comptes d'une entreprise en exploitation.

## Identité des documents

Le profil partagé est lu via `gama_company_action('get')`. Les modifications utilisent exclusivement la RPC administrateur `save`, avec contrôle de version. Le logo normalisé en PNG est limité à 800 000 caractères et son contenu n'est pas dupliqué dans l'audit (empreinte seulement). Le navigateur garde le profil en mémoire et le purge au changement de session.

La charte des documents est centralisée dans `gama-pdf-template.js`. Devis, factures internes, commandes fournisseurs, certificats et rapports de livraison, rapports de projets et étiquettes utilisent cette charte. Les extractions de données CSV/XLSX gardent leur structure. L'identité de l'application COCO ERP reste indépendante du logo de l'entreprise. Les PDF déjà téléchargés ne sont pas modifiés.
