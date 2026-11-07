# Politique MFA des administrateurs

La migration `20261107195615_audit_identity_policy.sql` prépare une politique serveur globale **inactive par défaut**. Elle n’enrôle aucun facteur et ne modifie aucun compte ni aucune session. La présence du code ne signifie pas que les administrateurs ont terminé leur enrôlement.

Dans **Sécurité de mon compte**, chaque titulaire ajoute et vérifie son authentificateur. La protection individuelle persistante existante reste en place. Un administrateur peut ensuite ouvrir **Protection obligatoire des administrateurs** : l’activation exige que tous les administrateurs actifs non bannis possèdent un facteur vérifié, une reconnaissance explicite de la récupération préparée et testée, puis une nouvelle preuve TOTP liée à cette activation. Les comptes non préparés ne doivent pas être verrouillés par une modification SQL manuelle de la politique.

Après activation, `erp_mfa_ok` exige AAL2 pour tout administrateur, y compris les nouveaux comptes. La RPC personnelle `coco_identity_policy('status')` fonctionne à AAL1 avant les lectures de profil, afin de permettre l’enrôlement. Elle ne renvoie aucun nom, identifiant de facteur, secret ni donnée métier. La connexion attend la vérification avant de charger le profil ; annuler l’enrôlement supprime le facteur non vérifié créé pour cette tentative, puis ferme la session. Un rechargement nettoie la tentative non vérifiée du même onglet ; les facteurs TOTP non vérifiés de plus de quinze minutes sont également retirés avant une nouvelle tentative. Aucun facteur vérifié n’est supprimé par ce nettoyage ; seul l’identifiant non secret de la tentative courante est conservé temporairement dans sessionStorage. Un statut absent ou invalide empêche l’ouverture de la session applicative. Déployer donc la migration avant les actifs qui l’utilisent.

## Authentification récente d’une opération

`ArchitectIdentity.withStepUp(action, resource, callback)` retourne le résultat du callback. Lorsque la politique est active, le serveur crée une demande liée à l’acteur, à sa session Auth, à l’action et à la ressource ; une nouvelle vérification TOTP postérieure à sa création l’approuve. L’opération sensible consomme sa propre preuve, une seule fois, dans les cinq minutes. L’activation de la politique impose ce mécanisme même lorsque la politique est encore inactive. Les demandes ne sont pas accessibles directement aux rôles API et les reçus expirés sont purgés.

L’export applicatif utilise `backup_export/all` et conserve ses gardes de module et d’action. Les modifications de droits utilisent `identity_admin` avec une ressource précise : `profile:<uuid>` pour le rôle, le profil d’accès, l’activation ou la suppression d’un compte ; `access-profile:<role>` et `access-profile:new:<nom>` pour les modèles de modules ; `action-rights:<role>` pour les restrictions d’action d’un rôle, y compris leur sauvegarde en lot ; `accounting-rights:<uuid>` pour les droits comptables, y compris le périmètre complet et les paiements ; `app-module:<id>` pour les modules de l’entreprise ; `tms-rights:<uuid>` pour les affectations TMS. Des triggers sur les tables vérifient les changements effectifs, y compris les écritures directes autorisées par l’API. Les mises à jour sans changement de droits, comme un nom, restent ordinaires.

Les décisions B2B des administrateurs utilisent `b2b-access:<client>`, `b2b-member:<client>:<profil>` et `b2b-approval:<client>:<profil>`. Les opérations métier des comptes clients conservent leurs contrôles propres. Les invitations et créations de comptes vérifient une preuve avec le JWT de l’appelant **avant** toute création Auth ou tout envoi d’e-mail, puis utilisent les accès techniques du serveur. Leur ressource est `identity-edge:` suivie de SHA-256 du tableau JSON canonique `[opération, email normalisé, rôle effectif, client ou chaîne vide]`. Une invitation B2B peut finaliser une seule fois son lien au client : cette finalisation doit correspondre exactement à l’e-mail invité, au client, à l’acteur et à la session de la preuve consommée. Une autre modification de membre demande une autre preuve.

Une opération SQL peut modifier le même droit en plusieurs instructions internes : sa preuve est alors réutilisable uniquement pour le même acteur, la même session, la même action, la même ressource et le même identifiant de transaction PostgreSQL. Une autre requête ne peut pas la rejouer. Les réessais déjà idempotents d’une commande TMS ou d’une suppression terminée conservent leur résultat. Les créations techniques Auth sans acteur humain et l’amorçage restent possibles ; elles ne permettent pas à un appelant authentifié de contourner les contrôles avec un identifiant fourni dans son payload.

En politique inactive, les vérifications récentes conservent le comportement précédent afin de permettre la préparation de la récupération ; cette phase ne doit pas être annoncée comme une obligation MFA déjà activée.

Les réglages Auth hébergés (longueur minimale, mots de passe compromis, limites et redirections) sont distincts de cette migration et doivent être constatés dans la configuration du projet. Les contrôles navigateur ne remplacent pas cette configuration serveur.

## Vérifications

```sh
node --test tests/identity-policy-hardening-db.test.cjs
npx playwright test tests/identity-policy-hardening.spec.js --workers=1
```

Les fixtures vérifient l’état initial non bloquant, les refus d’activation incomplets, le refus AAL1 après activation, le statut d’un nouvel administrateur, les preuves trop anciennes/d’une autre session/d’une autre action, les écritures de droits via RPC et directes, les auto-modifications autorisées, les opérations comptables composées, les invitations B2B et la consommation unique entre requêtes. Les parcours navigateur vérifient l’enrôlement avant le profil, l’annulation, la vérification récente et l’activation incomplète. Aucun compte réel n’est modifié par ces tests.
