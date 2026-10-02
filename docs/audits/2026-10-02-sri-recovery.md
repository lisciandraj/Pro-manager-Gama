# Reprise SRI du 2 octobre 2026

## État établi avant la reprise

Le contrôle s'appuie sur le dépôt et les réponses directes GitHub/Supabase.
Les annonces de corrections dans la conversation interrompue ne sont pas une
preuve d'enregistrement ni de déploiement.

| Élément | Préparé | Enregistré | Testé | Déployé |
| --- | --- | --- | --- | --- |
| Socle SRI, sélection, profil fiscal et liens factures/paiements | Oui | `main`, intégration `15c701d9ac832f3fb9fd1a353a360773ba9f8ca2` | Contrôles et CI du socle réussis | GitHub Pages ; dernier run `36903322800` sur `1c700ba73b5331f2e781325a8c622b70692e5f4c` |
| Migration SRI et sélection | Oui | Historique Supabase : `sri_invoice_workflow` 20260927220329, `sri_invoice_selection` 20261001092519 | Présence des tables, vue et RPC vérifiée | Oui, dans Supabase |
| Orchestration `gama-sri` | Oui | Code de `main` identique à la version déployée avant reprise | CI du socle ; contrôle du code déployé | Version 2 active, JWT requis |
| Stockage fiscal | Oui | Bucket `sri-documents` | Visibilité privée vérifiée | Oui |
| Quatre corrections annoncées le 2 octobre | Annoncées dans la conversation | Absentes de `main` et des branches consultées | Aucun résultat retrouvé | Non avant cette reprise |
| PostgreSQL/Redis/Carbone/Open API/passerelle Python | Recette Compose présente | Sources et exemples enregistrés | Tests du connecteur avec fixtures | Hébergement réel non vérifié |
| Profil SRI et émission réelle | Écrans disponibles | Zéro profil, zéro dossier `sri_invoice_issues`, zéro document `sri_electronic_documents` | Aucun test fiscal réel démontré | Non opérationnel |

Le contrôle direct des données trouve 14 factures internes, un RUC entreprise de
11 chiffres et 8 clients dont un sans identification. Ces données ne sont pas
modifiées par la reprise ; l'identité légale ne peut pas être déduite du code.

## Corrections reprises

- Champ fournisseur `RUC Proveedor` dans le XML et le DTO Open API, selon l'annexe
  26 de la fiche technique SRI 2.34, page 135.
- Envoi groupé : consultation unique après un POST en attente, puis continuation
  uniquement après autorisation vérifiée. Arrêt sur rejet, attente ou incertitude.
- Rejets consultables avec le même dossier et la même clé, sans réémission ni
  retour au brouillon. Une réponse en attente n'efface pas le rejet.
- Diagnostic technique précis et texte explicite sur ses limites fiscales.

Les contrôles utilisent des bases isolées et des réponses simulées. Ils ne
remplacent pas un essai avec certificat réel sur les services SRI `pruebas`.
Aucune migration supplémentaire n'est nécessaire pour ces corrections.

Validation locale de cette reprise : compilation, sources, types, liens de
documentation, historique des migrations, fichiers générés et budget de démarrage
réussis ; 149 tests Node/base, 20 tests Python et 14 parcours navigateur SRI
réussis (dont mobile, droits, lots, rejets et configuration). Le déploiement de
la reprise doit être rapproché des résultats de la PR, sans le déduire de ces
contrôles locaux.

## Plan d'action restant, dans l'ordre

1. **Propriétaire / comptable** : corriger le RUC de l'entreprise avec le vrai
   numéro à 13 chiffres ; confirmer raison sociale, adresse, régime, obligation
   comptable, établissement, point d'émission, RUC du fournisseur logiciel et
   compatibilité avec les factures ordinaires (01). Compléter l'identification du
   client concerné. Ne pas utiliser un RUC de test inventé pour l'entreprise.
2. **Propriétaire / administrateur serveur** : fournir un serveur privé Linux
   avec Docker et HTTPS, puis un certificat `.p12` valide et son mot de passe via
   un canal de secrets serveur. Ne jamais les déposer dans Git ou le navigateur.
3. **Administrateur serveur** : appliquer la recette
   [de déploiement coordonné](../../services/sri/deploy/README.md) au commit
   de cette livraison : volumes privés PostgreSQL/Redis/certificats/XML/PDF,
   Open API épinglé, Carbone compatible par digest et passerelle Python. Créer
   les comptes privés dédiés ; confirmer l'absence d'identifiants d'exemple.
4. **Administrateur serveur** : configurer l'émetteur et le certificat amont,
   les identifiants restreints et le secret HMAC partagé avec `gama-sri`.
   Valider HTTPS et le statut technique sans activer d'émission. Vérifier les
   endpoints `celcer.sri.gob.ec`, la réception sans retry et le mode synchrone
   amont ; conserver `SRI_PRODUCTION_ENABLED=false`.
5. **Administrateur Coco** : enregistrer le profil dans Configuration →
   Facturation SRI, en `pruebas`. Confirmer que l'instantané reprend l'identité
   validée, la bonne série fiscale et les données complètes du client.
6. **Recette technique supervisée** : vérifier XML contre le XSD officiel,
   signature XAdES-BES avec le certificat réel, présence de `RUC Proveedor`
   et rendu RIDE Carbone (montants, taxes, identité et clé). Confirmer que le
   digest choisi contient le convertisseur PDF nécessaire.
7. **Recette fiscale en pruebas** : activer seulement les essais supervisés ;
   préparer une facture représentative, envoyer une fois, consulter la même
   clé jusqu'au résultat, vérifier l'archivage privé XML/RIDE et le lien avec
   la facture interne. Tester rejet, timeout, consultation sans doublon et
   reprise après archivage partiel. Vérifier la remise au client avec une
   adresse de test explicitement choisie.
8. **Exploitation** : sauvegarder et restaurer en environnement isolé les bases,
   volumes de certificats et archives, puis documenter les preuves de recette.
   La production fiscale reste distincte des publications du site et nécessite
   une validation et une activation explicites après les essais réussis.

Les avoirs/retours, guías/TMS et retenues/finance restent hors du périmètre livré.
Leur raccordement suit la validation opérationnelle des factures ordinaires.
