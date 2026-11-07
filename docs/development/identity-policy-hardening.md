# Politique MFA des administrateurs

La migration `20261107195615_audit_identity_policy.sql` prépare une politique serveur globale **inactive par défaut**. Elle n’enrôle aucun facteur et ne modifie aucun compte ni aucune session. La présence du code ne signifie pas que les administrateurs ont terminé leur enrôlement.

Dans **Sécurité de mon compte**, chaque titulaire ajoute et vérifie son authentificateur. La protection individuelle persistante existante reste en place. Un administrateur peut ensuite ouvrir **Protection obligatoire des administrateurs** : l’activation exige que tous les administrateurs actifs non bannis possèdent un facteur vérifié, une reconnaissance explicite de la récupération préparée et testée, puis une nouvelle preuve TOTP liée à cette activation. Les comptes non préparés ne doivent pas être verrouillés par une modification SQL manuelle de la politique.

Après activation, `erp_mfa_ok` exige AAL2 pour tout administrateur, y compris les nouveaux comptes. La RPC personnelle `coco_identity_policy('status')` fonctionne à AAL1 avant les lectures de profil, afin de permettre l’enrôlement. Elle ne renvoie aucun nom, identifiant de facteur, secret ni donnée métier. La connexion attend la vérification avant de charger le profil ; annuler l’enrôlement ferme la session. Un statut absent ou invalide empêche l’ouverture de la session applicative. Déployer donc la migration avant les actifs qui l’utilisent.

## Authentification récente d’une opération

`ArchitectIdentity.withStepUp(action, resource, callback)` retourne le résultat du callback. Lorsque la politique est active, le serveur crée une demande liée à l’acteur, à sa session Auth, à l’action et à la ressource ; une nouvelle vérification TOTP postérieure à sa création l’approuve. L’opération sensible consomme sa propre preuve, une seule fois, dans les cinq minutes. L’activation de la politique impose ce mécanisme même lorsque la politique est encore inactive. Les demandes ne sont pas accessibles directement aux rôles API et les reçus expirés sont purgés.

L’export applicatif utilise `backup_export/all` et conserve ses gardes de module et d’action. En politique inactive, le mécanisme retourne le comportement précédent afin de permettre la préparation de la récupération ; cette phase ne doit pas être annoncée comme une obligation MFA déjà activée. Le mécanisme fournit aussi le périmètre `identity_admin` pour raccorder les autres décisions sensibles ; il ne prétend pas protéger automatiquement toutes les opérations qui ne le consomment pas encore.

Les réglages Auth hébergés (longueur minimale, mots de passe compromis, limites et redirections) sont distincts de cette migration et doivent être constatés dans la configuration du projet. Les contrôles navigateur ne remplacent pas cette configuration serveur.

## Vérifications

```sh
node --test tests/identity-policy-hardening-db.test.cjs
npx playwright test tests/identity-policy-hardening.spec.js --workers=1
```

Les fixtures vérifient l’état initial non bloquant, les refus d’activation incomplets, le refus AAL1 après activation, le statut d’un nouvel administrateur, les preuves trop anciennes/d’une autre session/d’une autre action et leur consommation unique. Les parcours navigateur vérifient l’enrôlement avant le profil, l’annulation, la vérification récente et l’activation incomplète. Aucun compte réel n’est modifié par ces tests.
