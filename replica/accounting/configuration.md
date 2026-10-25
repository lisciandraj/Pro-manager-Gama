# Suite de l'intégration — configuration et relevés

Référence inchangée : Odoo **19.0 Enterprise**, documentation officielle consultée le **24 octobre 2026**. Implémentation native originale dans la stack Coco. Les composants, rôles, données et références internes existants restent la base de travail.

## Sources et règles observées

| Source officielle 19.0 | Règle étudiée | Parcours Coco |
| --- | --- | --- |
| [Plan comptable](https://www.odoo.com/documentation/19.0/applications/finance/accounting/get_started/chart_of_accounts.html) | Types détaillés et groupes de comptes ; regroupement à partir des codes | Configuration → Types, groupes, séquences et verrouillages → Types et comptes / Groupes |
| [Clôture et dates de verrouillage](https://www.odoo.com/documentation/19.0/applications/finance/accounting/reporting/year_end.html) | Dates inclusives, décalage de la date comptable, exceptions administrateur personnelles ou globales, durée et motif ; verrouillage dur irréversible | Même écran → Verrouillages |
| [Séquences](https://www.odoo.com/documentation/19.0/applications/finance/accounting/customer_invoices/sequence.html) | Numéro final à la validation, formats et périodicité ; renumérotation de masse distincte | Même écran → Séquences ; le lot ne renumérote pas l'historique |
| [Rapprochement](https://www.odoo.com/documentation/19.0/applications/finance/accounting/bank/reconciliation.html) | Import et contrôle des mouvements avant rapprochement | Banque et caisse → Importer CSV → Affecter les colonnes |

Les 19 types couvrent les six sous-types d'actif, quatre de passif, deux de capitaux propres, deux de produits, quatre de charges et le hors bilan. Les comptes historiques ne reçoivent pas de sous-type inventé : ils restent « À classifier » jusqu'au choix d'une personne autorisée. Le hors bilan participe à la balance générale, sans entrer dans le bilan ou le compte de résultat. Les rapports légaux propres aux localisations demeurent un écart séparé de la matrice.

Les groupes possèdent une plage de préfixes de même longueur. Le compte choisit la plage la plus précise ; les parents sont recalculés à partir des plages contenantes. Les chevauchements au même niveau et les cycles sont refusés. La balance affiche ouverture, débit, crédit et clôture, avec accès au grand livre filtré. Le filtre de groupe s'applique à ses comptes, ses sous-groupes, ses totaux et l'export. Le total d'un parent comprend ses enfants : ces lignes ne doivent pas être additionnées entre elles.

## Numérotation et références

La référence interne ERP/processus reste stable dans `erp_reference` et dans le registre documentaire ; les liens reposent sur les UUID existants. Une politique de journal activée attribue un numéro comptable à la validation. Le livre affiche les deux références lorsqu'elles diffèrent et accepte la recherche par chacune.

Variables configurables : `{JRN}`, `{YYYY}`, `{YY}`, `{MM}`, `{FY}`. La périodicité peut être continue, mensuelle, annuelle ou par exercice selon le mois de début déjà configuré dans Coco. Les compteurs sont transactionnels ; les appels concurrents sont sérialisés et les collisions de formats sont évitées. Une validation annulée par erreur de contrôle ne consomme pas son numéro comptable. Les compteurs de références ERP existants conservent leur fonctionnement compatible.

Le format est modifiable pour les prochaines validations. Une politique déjà utilisée conserve sa périodicité et son point de départ ; le lot ne fournit pas encore la détection automatique du format depuis une référence éditée ni la renumérotation de masse Odoo. **B04 reste partiel** et ne devient pas une exclusion.

## Verrouillages

Dates inclusives : tout, ventes, achats, taxes, définitif. Le contrôle serveur couvre la validation manuelle et les écritures automatiques. Les lignes de taxe sont identifiées aussi par leurs comptes, même sans `tax_id` explicite. La date comptable effective et la date demandée sont conservées dans l'historique des ajustements ; les dates des documents sources ne sont pas réécrites.

Les exceptions sont personnelles ou globales, à durée déterminée ou explicitement sans expiration ; elles peuvent conserver un verrouillage jusqu'à une date antérieure. Motif et auteur sont obligatoires. Une nouvelle date de verrouillage invalide les exceptions accordées à sa version précédente ; une simple modification du motif ne les invalide pas. Révocations et expirations sont contrôlées côté serveur. Le verrouillage définitif exige une confirmation distincte et ne peut être réduit ni recevoir d'exception.

Le verrou mensuel historique de Coco reste un contrôle supplémentaire : une exception de date ne rouvre pas un mois fermé. L'administrateur doit utiliser le parcours de réouverture existant si cette opération est nécessaire. Aucun réglage de production n'est activé par la migration.

Toutes les mutations de ce nouvel écran nécessitent les droits existants et un auteur humain. Les propositions spécifiques Agent Coco ne sont pas encore raccordées à cet écran et restent visibles dans l'écart N02. Les paramètres ne sont pas activés par une suggestion IA non approuvée.

## Import CSV

Deux modes : reconnaissance actuelle et affectation manuelle. Le choix porte sur la première ligne à utiliser, la présence d'un en-tête, le séparateur, le séparateur décimal et les colonnes date/référence/description/montant ou débit/crédit. Les colonnes sont adressées par position, même si leurs titres se répètent. L'aperçu montre les valeurs originales puis les mouvements interprétés. Les affectations dupliquées, champs manquants, tailles excessives, dates impossibles et lignes malformées bloquent l'import complet.

Les fichiers sans en-tête conservent leur première transaction. Les références gardent leurs zéros initiaux et les descriptions entre guillemets peuvent contenir des sauts de ligne. Le serveur reste responsable des droits, de l'atomicité, des limites et de la détection des doublons ; affecter des colonnes ne crée aucune écriture ou encaissement. Les autres formats bancaires restent dans F04.

## Architecture et migration

Façade publique invocateur `gama_accounting_configuration` ; traitement privé avec Auth, MFA, rôle, périmètre complet et permissions effectives, y compris restrictions générales d'actions et d'export. Les six tables privées ont RLS et aucun accès direct client. Les réglages métier et ajustements de date utilisent les captures d'historique existantes, avec liens vers leur écran et leur dossier. Les compteurs restent techniques.

La configuration prend un verrou exclusif commun ; les écritures prennent son verrou partagé dès leur insertion. Le mois de la date comptable ajustée est également verrouillé et revérifié, afin de sérialiser la clôture avec la validation. Les commandes sont liées à l'acteur, à l'action et au contenu de leur clé de requête.

La migration est additive : sous-type nullable, élargissement de la famille hors bilan, tables privées vides, fonctions et contrôles. Elle n'ajoute aucun compte, groupe, numéro, verrouillage, facture ou paiement en production. La procédure de retour de l'interface et de conservation des écritures reste celle de [deploy.md](deploy.md). Une suppression des nouveaux paramètres après usage doit conserver les numéros, les exceptions et leurs preuves ; aucune suppression automatique n'est prévue.

## Vérification

Tests isolés : `tests/accounting-configuration-db.test.cjs`, `tests/bank-statement.test.cjs`, `tests/accounting-configuration.spec.js` ; concurrence ajoutée à `tests/accounting-plans-concurrency.test.cjs`. Le parcours complet vente → banque et les suites comptables existantes restent dans les contrôles de régression.

Scénarios indépendants : produit de 100 avant février puis 30 en février → ouverture du groupe de produits -100, crédit 30, clôture -130 ; séquences annuelles et mensuelles remises à 1 ; exercice débutant en juillet → juin 2026 appartient à 2025, juillet à 2026 ; verrou au 31 mai → écriture demandée le 15 mai datée au 1er juin ; import mappé de 19,25 USD rejoué sans second mouvement et sans nouveau cash.

Les 77 tests ciblés du contrôle local ont réussi. La [CI 40183687082](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40183687082) valide 70 parcours navigateur, dont les neuf nouveaux FR/ES/EN × 390/768/1440, et la concurrence PostgreSQL 17 réelle. La suite générale compte 572 tests : 570 réussis, zéro échec, deux SKIP de services dédiés. L'interface partagée compte 430 réussites. Le navigateur local n'a pas pu être téléchargé ; les preuves navigateur proviennent du runner CI, pas des seuls tests serveur.

Migration appliquée : **20261025102114_accounting_configuration_parity**,
32 547 octets, SHA-256 `e84690a18d3ef6c4069f0e13b393c93ec9134c2ada4a098a390c61438a50bd78`,
identique au SQL enregistré par Supabase. Les [contrôles après migration](evidence/configuration-after-migration.json)
montrent des réglages vides, les droits attendus et des données historiques
inchangées. Le détail de livraison et ses limites figurent dans
[results-configuration.md](results-configuration.md).

Défauts reproduits et corrigés avant publication : le mécanisme historique de référence Coco rétablissait son alias après une validation numérotée ; le numéro final est désormais conservé lors des mises à jour suivantes. Le contrôle d'actions ne possède pas d'action générique `close` : la nouvelle API utilise les droits de clôture comptables et la restriction générique de validation existante, sans supprimer les contrôles de rôle ou MFA.

Les tests navigateur ont aussi révélé des aperçus CSV défilants inaccessibles au
clavier sur téléphone. Leurs régions sont désormais nommées et focalisables ;
les trois langues passent le contrôle axe sans supprimer cette règle.

Correctif de référence : [Autres charges et garde-fous hors bilan](off-balance.md). Le premier lot de configuration exposait 18 types ; le dix-neuvième est confirmé par la référence technique 19.0. Une écriture hors bilan doit rester séparée des comptes ordinaires, des taxes et du rapprochement.
