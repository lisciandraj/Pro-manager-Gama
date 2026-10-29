# Livraison des améliorations restantes

Base : f41553c (catalogue publié). Stack, identifiants, RPC et registres conservés.

## Reconnaissance complémentaire

S2 était classé partiel : `sales_fulfillment_options` et `gama_fulfillment_action`
gèrent déjà les propositions, accords externes et ancien chemin client désormais désactivé, substitutions de reliquats
non réservés, livraisons partielles et dates promises. La nouvelle livraison étend
ce parcours ; elle ne crée pas de registre de substitution. Le devis accepté reste
immuable. Les options et événements du dossier conservent l'accord modificatif.

## Intégration

| Besoin | Source réutilisée | Modification |
| --- | --- | --- |
| Q4 Prochaine activité | sales_activities / dossier | Projection paginée dans la liste des devis ; activité ouverte la plus proche, auteur/responsable, date locale |
| Q5 Marge par ligne | gama_commercial_planning / quote_margin | Même calcul serveur, détail par ligne sous droits financiers ; coût absent reste inconnu |
| S1 Disponibilité datée | stock_quants, sales_reservation_links, purchase_order_lines | Projection FIFO dans l'ordre du moteur d'allocation actuel ; réservation physique séparée ; propositions de dates dans les options existantes |
| S2 Substitution approuvée | sales_fulfillment_options / gama_fulfillment_action | Empreinte des conditions, source tarifaire, motif manuel, contrôles de crédit/marge et unités, nouvelle lecture à l'accord |
| S3 Exceptions par rôle | gama_live_alerts / Dashboard / Notifications | Activités échues, accords en attente et promesses dépassées ; mêmes droits, filtres et suivi existants |

## Disponibilité et dates

La projection déduit les réservations une seule fois. Elle attribue le disponible
libre puis les arrivages confirmés aux reliquats non réservés, dans l'ordre
`created_at, order_id, line_id`, identique à l'allocation automatique. Une simulation
de devis passe après les commandes confirmées. Une commande conserve ses réserves.
Les achats brouillons, sans date ou déjà en retard ne donnent pas une date fiable.
Les services n'ont pas de disponibilité physique présumée.

Les jours de préparation et de transport sont saisis explicitement en jours
calendaires. Aucune durée de trajet à Quito ou interurbaine n'est inventée. Les
dates sont calculées dans le fuseau de l'entreprise ; une date reste une date
civile. La promesse nécessite une commande confirmée et un accord explicite. Le
serveur recalcule la faisabilité à la proposition puis à l'accord. Un retard amont
ou un changement commercial impose une nouvelle proposition. Une promesse partielle
porte sur la quantité convenue ; son alerte se ferme sur la livraison signée de
cette quantité cumulée aux expéditions antérieures, sans englober le reliquat non promis.

## Sécurité et transitions

Lectures bornées, API publiques invoker et helpers privés contrôlés. Vendeur/admin
peuvent proposer selon leurs permissions existantes ; magasinier consulte le
planning sans coûts ; les clients B2B gardent les droits du portail séparé et ne peuvent pas utiliser les RPC internes. L’accord est enregistré par le vendeur avec sa référence.
Pas de nouvelle clé, service externe, envoi client ou paiement automatique.

Substitution : proposée → acceptée/rejetée/retirée. À l'acceptation : même verrou
transactionnel que la préparation, quantité encore non réservée/non expédiée,
ligne non facturée, conditions inchangées, accord référencé, contrôles commerciaux
et crédit, puis moteur existant. La transaction entière est annulée en cas d'échec.
Les anciennes options sans empreinte doivent être reproposées avant acceptation ;
elles restent consultables et peuvent être rejetées ou retirées.

Les changements métier gardent les événements existants et la provenance Agent
Coco lorsqu'ils passent par la passerelle IA. La livraison ne modifie aucune
donnée métier réelle. La migration technique reste dans le registre des migrations.

## Validation et retour arrière

Tests isolés : activités terminées/non datées, coûts inconnus et droits, quantités
et conditionnements, allocations concurrentes sur un même arrivage, achats en
retard, accord devenu obsolète, idempotence, crédit, historique, FR/ES/EN et mobile.
Régressions ventes, préparation, factures/livraisons partielles et portail.

Déploiement additif SQL avant les actifs web, après contrôles verts. Retour arrière
du frontend par réversion ; conserver les colonnes/snapshots ajoutés pour ne perdre
aucun accord. Les gardes serveur restent actives et compatibles avec les lectures
existantes. Publication vérifiée par le commit et les actifs servis.

## Suite du portail

Le report de l'accord client B2B est traité par `portal-architecture.md` :
consentement sur l'option existante puis application commerciale, sans réactiver
l'ancien accès client ERP. Le calendrier métier reste celui défini dans ce lot
(jours calendaires) ; aucun nouveau calendrier ni automatisme client n'est ajouté.
