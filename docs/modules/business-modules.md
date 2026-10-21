# Contrats, dépenses et consultations fournisseurs

Les routes `contracts` et `expenses` sont déclarées dans le registre commun et chargent `CocoBusiness` à la demande, avec leur feuille de style. Les libellés suivent la langue ES/FR/EN. Les consultations s'ouvrent depuis la barre d'outils Achats. Trésorerie à 13 semaines et rentabilité par commande/client sont accessibles depuis le tableau de bord et Comptabilité.

## Contrats

Un contrat associe un client, une adresse, des produits, une durée, une fréquence hebdomadaire ou mensuelle et des prix convenus ou recalculés au tarif client. Chaque échéance prépare au maximum un **brouillon** via le circuit de vente existant. Le taux de taxe est repris sur la fiche produit au moment de préparer la nouvelle commande, y compris lorsque le prix hors taxes est fixé au contrat. Les commandes historiques restent inchangées. Le stock n'est réservé qu'à la confirmation habituelle. L'historique donne accès aux commandes générées. Une échéance déjà traitée ne peut être réutilisée.

La préparation automatique s'exécute à la minute 25 de chaque heure, selon le fuseau de l'entreprise. Elle recontrôle les droits actuels du créateur ; désactivation du compte, retrait des droits ou MFA exigée peuvent la bloquer. L'écran signale alors une vérification nécessaire et permet une préparation interactive. Les échéances anciennes ne créent pas de rattrapage en masse : une seule commande est préparée puis la prochaine date future est calculée en conservant l'ancrage de fin de mois. Les programmes du portail client conservent leur confirmation par le client.

## Dépenses et justificatifs

Le module reprend les dépenses de Comptabilité et Fleet. Il ajoute le collaborateur RH, le véhicule, le motif et le circuit brouillon → soumission → validation → remboursement, avec refus motivé. Les justificatifs PDF/JPEG/PNG/WebP sont limités à 2 Mo dans le formulaire. La lecture OCR réutilise le service installé et exige une vérification humaine des données proposées. Un original OCR ne peut alimenter à la fois une dépense et une facture fournisseur.

Un frais avancé par un collaborateur est comptabilisé en dette lors de la validation ; son remboursement solde cette dette et crédite le compte financier choisi. Il ne crée aucune deuxième charge. Une annulation motivée du remboursement contre-passe son écriture et réouvre la somme à rembourser ; une contre-passation depuis le journal produit le même résultat. L'action enregistre un paiement déjà effectué ; elle n'effectue pas de virement. La trésorerie à 13 semaines comprend les remboursements validés en attente, et les retire après paiement. Les frais payés directement par l'entreprise sont comptabilisés sur leur compte financier à la validation.

Accès par défaut : administration. Le serveur exige aussi le périmètre comptable complet et les droits de création, modification, validation ou paiement correspondants. Les montants soumis ne peuvent plus être modifiés depuis les anciens écrans. Les pièces originales restent soumises aux droits de Comptabilité.

## Consultations et conditions fournisseurs

Une consultation contient un ensemble de produits et une date nécessaire. Chaque fournisseur présente une offre complète : prix, minimums, multiples de conditionnement, transport, validité, délai et conditions de paiement. La comparaison applique les quantités réellement achetables et affiche le total hors taxes, transport compris, en séparant les devises.

Le choix motivé d'une offre valide dans la devise de l'entreprise crée un seul brouillon d'achat par le circuit existant. Les conditions et le transport sont conservés dans les notes. Le transport n'est pas incorporé artificiellement au prix des produits ; il doit être porté sur la facture fournisseur lorsqu'il s'applique. Le circuit de validation et réception des achats reste en vigueur.

## Sécurité et vérification

Migration : `20261020193647_business_modules_contracts_expenses_sourcing.sql`. Les cinq tables privées utilisent RLS, sans accès direct aux rôles API ; seuls les RPC contrôlés sont accordés aux utilisateurs authentifiés. Les opérations sont enregistrées dans l'historique des modules. Les formulaires utilisent versions optimistes, clés stables et verrouillages transactionnels pour éviter écrasements et doubles créations.

`tests/business-modules-db.test.cjs` restaure les migrations dans une base isolée et vérifie contrats, délégation, droits, justificatifs, OCR, écritures équilibrées, prévisions et consultations. `tests/business-modules.spec.js` vérifie les formulaires, les fichiers, les erreurs et le petit écran. Aucun scénario de test n'écrit de données métier dans la base réelle.
