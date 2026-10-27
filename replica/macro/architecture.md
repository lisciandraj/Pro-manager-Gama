# Architecture du travail commun

Reconnaissance : [recon.md](recon.md). Stack existante : JavaScript classique
chargé à la demande, routeur Coco, ArcUI, ArcData et PostgreSQL/Supabase.

La route `workhub` dispose de son contrôle de module. La façade
`public.coco_workhub(action, data)` est **SECURITY INVOKER** : les recherches,
résolutions et agrégations réutilisent les RLS des tables métier. Les fonctions
privées d'écriture vérifient le profil, la MFA, l'appartenance au canal et le rôle
de propriétaire. Elles ne modifient aucun registre commercial ou financier.

Six tables privées : canaux, membres, messages, liens typés, classement personnel,
reçus d'idempotence. Les listes sont bornées et paginées ; aucun miroir métier
dans localStorage. Les requêtes d'une ancienne session sont ignorées. Les
identifiants des sources sont résolus à chaque lecture sous les droits actuels.
Une référence n'accorde aucun droit supplémentaire sur son document.

| Action RPC | Parcours | Contrôle |
| --- | --- | --- |
| bootstrap | F01/F02 | Profil interne actif, module et MFA ; canaux limités aux membres. |
| inbox / search | F01/F05/F07 | RLS sources, classements personnels ; pagination. |
| channel / context | F02/F06 | Appartenance actuelle ; messages et liens bornés. |
| channel_create / member_set | F02 | Créateur / propriétaire ; collègues internes existants seulement. |
| message_create | F02/F04 | Membre ; fil du même canal, limites de texte, clé de requête. |
| task_create | F03 | Droits Projets ; moteur natif `gama_projects_action`, transaction atomique. |
| resolve / backlinks | F04 | Liste blanche des types, RLS du dossier, canaux du demandeur. |
| item_state | F05 | Propriétaire du classement ; aucune modification du statut métier. |

Les canaux et messages sont enregistrés dans l'historique Coco par les triggers
existants, avec visibilité limitée aux membres et sans copie du texte du chat.
Le contexte Agent Coco reste un brouillon envoyé volontairement ; les écritures
métier conservent les validations existantes. Le relais mail reste la source des
propositions mail, et ne prétend pas être une synchronisation Gmail complète.

Ordre : S01/S02 et permissions → F02/F03 → liens et recherche → F05/F06 → tests
SQL isolés, navigateur ordinateur/téléphone, contrôles communs, CI et publication.
