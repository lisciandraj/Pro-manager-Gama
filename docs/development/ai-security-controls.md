# Contrôles IA, OCR et consultation SRI

État : 7 novembre 2026. Les limites du fournisseur et son contrat de traitement
restent des réglages d’exploitation ; les contrôles ci-dessous sont ceux du code.
Aucun secret n’est enregistré dans cette documentation.

## Budget commun avant appel

La migration `audit_ai_budget` crée un contrôle d’admission partagé entre analyse,
préparation stock et OCR. Chaque appel payant à Responses — y compris les tours
successifs du modèle — obtient une réservation avant le réseau fournisseur.
Un verrou transactionnel commun borne les admissions simultanées. Un refus ou
une erreur du service de quota empêche l’appel ; le navigateur ne peut pas appeler
la RPC de réservation, accordée uniquement à `service_role`.

Les réglages privés `ai_provider_policy` définissent par défaut : 100 appels/jour
UTC, 10 USD/jour de budget de réservation, trois appels simultanés, une durée de
bail de 120 secondes, 512 000 jetons d’entrée estimés et 9 000 jetons de sortie
maximum. Chaque appel réserve au moins 0,25 USD. Seul `gpt-4.1-mini` est inscrit
initialement, avec des coefficients conservateurs d’un et quatre micro-USD par
jeton d’entrée/sortie. L’exploitant doit vérifier les tarifs et besoins avant
activation ; un nouveau modèle est refusé tant qu’il n’a pas de coefficients
explicitement revus dans `ai_provider_models`.

Le nombre d’octets UTF-8 du JSON fournit une estimation prudente pour le texte.
L’OCR réserve un plancher de 250 000 jetons d’entrée : ce n’est **pas** un compteur
exact des jetons d’un PDF compressé ou d’une image. Les usages effectifs retournés
par le fournisseur majorent la charge retenue si nécessaire. Les réservations,
les appels échoués et les timeouts restent imputés ; une réponse tardive peut
finaliser un bail expiré. Une admission ultérieure considère les charges déjà
retenues. Le plafond du compte fournisseur doit également être activé : un
budget de réservation applicatif ne garantit pas, à lui seul, le montant d’une
facture fournisseur, notamment pour les médias dont le coût exact est inconnu
avant traitement.

Le `finally` du relais libère la concurrence à la fin d’un appel, y compris en
cas d’erreur. Si cette finalisation échoue, le bail expire sans rembourser
aveuglément une génération potentiellement facturée. La rétention technique est
90 jours, avec purge bornée quotidienne. Les métriques contiennent acteur,
opération, modèle, compteurs et états ; jamais question, réponse, fichier,
jeton d’authentification ou clé fournisseur. L’effacement d’un profil anonymise
la référence d’acteur sans effacer les charges de la journée.

## Minimisation avant transmission

Le catalogue transmis au modèle est filtré d’après la question humaine avant
l’appel. Une question produit/stock ne reçoit pas de catalogue RH ou financier,
de coordonnées personnelles ni de synthèse RH. Une question RH n’ouvre pas les
salaires tant qu’elle ne demande pas la paie/rémunération. Les projections,
filtres, tris et regroupements des outils sont vérifiés contre ce catalogue
réduit ; une demande sans projection ne rétablit pas les colonnes exclues.

Les détails des créances sont limités aux champs nécessaires. Les réponses
historiques ne sont plus renvoyées au fournisseur ; les questions de contexte
hors de la portée personnelle/RH courante sont exclues. Les outils conservent le
jeton du demandeur et les RPC/RLS actuelles : ce filtrage de divulgation ne
remplace aucune autorisation serveur. Les documents explicitement demandés
peuvent contenir des données personnelles ; le responsable des données conserve
le choix des usages autorisés, la politique de conservation et le contrat du
prestataire. `store:false` reste présent et n’est pas présenté comme une garantie
contractuelle de non-conservation par tous les systèmes du fournisseur.

## Clés de configuration IA versionnées

Une nouvelle configuration exige `GAMA_AI_ENCRYPTION_KEY` (au moins 32 caractères
aléatoires), distincte de `SUPABASE_SERVICE_ROLE_KEY`. Le chiffrement AES-GCM
versionné lie l’enveloppe à son identifiant et à son contexte. Les variables :

- `GAMA_AI_ENCRYPTION_KEY_ID` : identifiant courant, `primary` par défaut ;
- `GAMA_AI_ENCRYPTION_KEY` : clé courante ;
- `GAMA_AI_ENCRYPTION_KEYS` : objet JSON des anciennes clés versionnées encore
  nécessaires au déchiffrement ;
- `GAMA_AI_LEGACY_ENCRYPTION_KEYS` : liste JSON temporaire, au plus huit anciennes
  valeurs nécessaires pour les enveloppes historiques.

Le repli sur la clé de service ne sert qu’au **déchiffrement** des anciennes
valeurs. Une sauvegarde nouvelle n’utilise jamais ce repli. La réponse `status`
peut signaler `key_rotation_required`. Après avoir installé une nouvelle clé et
son identifiant, un administrateur authentifié peut appeler l’action
`rotate_key` de `gama-assistant-ia` : la valeur est déchiffrée puis rechiffrée côté
serveur, sans renvoi de clé au navigateur ni appel payant au modèle. Vérifier
ensuite `status` et un scénario de recette avant de retirer les anciennes clés.

Installer la même clé/version dans les deux fonctions assistant et OCR. Une
rotation de clé de service exige de conserver explicitement l’ancienne valeur
pour le seul déchiffrement historique jusqu’au rechiffrement ; ne jamais la
mettre dans le dépôt ou un journal. Le raccordement des secrets et leur rotation
réelle nécessitent le coffre et les droits de l’exploitant.

## Ordre de livraison et consultation SRI

1. Appliquer la migration de budget après validation sur base isolée ; vérifier
   la politique, le modèle réellement configuré et les capacités du fournisseur.
2. Installer les clés de chiffrement dédiées, puis livrer ensemble assistant,
   OCR et leurs modules partagés. Une RPC de budget indisponible ferme l’accès
   payant plutôt que de laisser passer un appel sans contrôle.
3. Rechiffrer les réglages historiques et vérifier les refus de quota en recette.
4. Pour SRI, déployer le relais à capacité dédiée puis coordonner la mise à jour
   de l’hôte privé avec `SRI_SUPABASE_PUBLISHABLE_KEY` et `SRI_RECONCILE_TOKEN`.
   Voir [service SRI](../../services/sri/README.md#automatic-consultation).

L’ancien parcours Edge SRI reste compatible tant qu’aucun token dédié n’est
provisionné. Quand ce token est installé, une ancienne clé globale n’est acceptée
que pendant une grâce explicite `SRI_LEGACY_RECONCILE_UNTIL`. Le nouveau worker ne
lit jamais la clé globale. Ne pas annoncer le retrait effectif de ce secret de
l’hôte privé avant d’avoir constaté cette mise à jour et sa consultation.
