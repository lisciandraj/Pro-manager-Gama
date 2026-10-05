# Revue des demandes Équateur — 5 octobre 2026

Le code des demandes ci-dessous est intégré à Coco ERP. La base, les fonctions
serveur et l'interface sont déployées sur le projet GAMA. L'état « intégré » ne
constitue pas une autorisation fiscale réelle ; les dépendances sont précisées
dans le tableau. Les corrections de cette revue complètent les adresses dans les
devis, la préparation automatique 07 et le détail des coûts TMS par client.

| Demande | Parcours dans l'ERP | État et limites pratiques |
| --- | --- | --- |
| Nota de crédito 04 | Retours → Reponer y preparar nota de crédito SRI | Remise en stock, avoir et brouillon 04 dans une transaction après réception/inspection ; facture originale autorisée requise. Émission : moteur privé. |
| Retención fournisseur 07 | Comptabilité → facture fournisseur ; Facturation SRI → politiques fournisseur | Préparation automatique si agent confirmé, fiscalité de la facture et taux datés revus ; reprise après revue fiscale ou politique fournisseur. Autorisation/solde fiscal : moteur privé. |
| Guía de remisión 06 | TMS → carte de tournée ; chauffeur → Guía de remisión | Marchandises et destinataires réels figés ; le chauffeur ne télécharge que la guía autorisée de sa tournée. Émission : moteur privé. |
| Liquidación de compra 03 | Facturation SRI → document d'achat | Personne avec cédula sans RUC, lignes réelles et totaux revus ; utilise le signataire privé avec certificat, pas le fournisseur Open API épinglé. |
| Reprise quand le SRI attend | Facturation SRI → consultation ; ordonnanceur du moteur privé | Même clé, sans nouvel envoi. L'ordonnanceur fonctionne une fois ses identifiants privés configurés ; l'écran consulte aussi les dossiers ouverts. |
| Retenues client depuis XML | Comptabilité → outils Équateur → Abonos y retenciones | XML 07 1.0/2.0 réellement autorisé vérifié par le moteur privé ; imputation groupée, archive et reprise sans doublon. Ne crée pas d'entrée bancaire. |
| ATS avec retenues, crédits et annulations | Comptabilité → contrôle fiscal → brouillon ATS | Opérations nationales courantes, retenues IR/IVA, crédits et annulations documentées pris en charge. Cas étrangers/spéciaux signalés ; export à réviser, sans dépôt automatique. |
| Formulaires 103/104 | Comptabilité → outils Équateur → Formularios 103 y 104 | Préparation depuis les écritures du mois, incluant IR de paie et retenues ; crédit antérieur/facteur à revoir. Aucun dépôt fiscal. |
| Rapprochement bancaire | Comptabilité → Banco y caja → CSV | Lecture de colonnes usuelles, suggestions, confirmation atomique du cobro et rapprochement. Les formats Excel/PDF ou propriétaires demandent une conversion CSV. |
| Crédit client bloquant | Ventes → confirmation du pedido | Blocage serveur sur échéances et exposition, contrôles sur lignes ; dérogation administrative liée au dossier et au risque actuel. |
| RUC/cédula et doublons | Contacts → création/modification client ou fournisseur | Chiffres de contrôle et identifiant normalisé contrôlés au serveur ; les données anciennes inchangées sont conservées. |
| Balance âgée et relances PDF | Contacts/Paiements → Balance por antigüedad ; Estado de cuenta y recordatorio | Non échu, 0–30, 31–60, 61–90, plus de 90 et échéance absente. Texte/PDF préparés ; envoi explicite via partage ou messagerie, PDF à joindre si nécessaire. |
| Plusieurs adresses de livraison | Contacts → adresses secondaires ; devis → Dirección de entrega guardada ; portail B2B | Adresses actives du client proposées ; destination figée dans le devis/demande et reprise par le pedido/TMS. |
| Mini/maxi sur 90 jours | Stock → réapprovisionnement → Revisar mínimos y máximos · ventas 90 días | Expéditions réelles, délai et réserve de sécurité ; validation par produit en un clic, recontrôlée au serveur. |
| Commandes de réappro par fournisseur et MOQ | Stock → réapprovisionnement → préparer les achats | Réservations, achats en route/brouillons, fournisseur, minimum de quantité et multiple de conditionnement pris en compte. Revue avant envoi. |
| Performance fournisseur | Fournisseurs → offres et performance | Délai final réel/promis, retard, première réception incomplète et taux associé. Absence de données indiquée. |
| Chauffeur et motifs d'échec | TMS → Mi ruta | Arrêts ordonnés, navigation/appel/photo/signature, incidents et reprogrammation. Accès limité à la tournée assignée. |
| Coût de livraison par client | TMS → Indicadores → Coste de entrega por cliente | Coût/km Flota figé × km vérifiés ou estimés, répartition uniforme par arrêt au centime ; regroupement client, recherche et pagination serveur. Coût/km absent, client inconnu et tournées sans arrêt signalés. |
| Fusion SAV/Retours | Retours → Posventa | Une navigation commune, routes/API historiques conservées ; l'activation du parent Retours conditionne les accès. |
| Paie équatorienne | RRHH → Nómina calculada para Ecuador | IESS, décimos au choix, réserve après un an, cotisations complémentaires et utilidades calculés au serveur avec paramètres versionnés à confirmer. IR salarié saisi/revu séparément. |
| Rol signé et fichier bancaire | RRHH → Rol de pagos / export bancaire | PDF et accusé signé par le compte salarié ; CSV des montants réellement dus et coordonnées revues. Signature de réception, pas certificat électronique qualifié ; aucun virement envoyé. |
| Portail B2B | Site web → Portal B2B ; site public → Mi empresa | Activation par entreprise/compte, prix propres, favoris, demandes, factures, preuves et état de compte ; accès ERP client fermé. |
| Direction sur une page | Tableau de bord → vue de direction | Ventes du mois, marge sur coûts historiques connus, cartera échue, dormant, ruptures et retards TMS, selon les droits. |
| Questions concrètes Intelligence | Coco Intelligence → clients à relancer / achats de la semaine | Données actuelles calculées sans clé IA ; liens vers l'action, sans envoi ni achat automatique. |

## Configuration restante pour les documents SRI

Le moteur privé doit être déployé avec cette version, le certificat du contribuable
et les identifiants serveur. Cela concerne l'émission 03/04/06/07, la vérification
des retenues XML reçues et la consultation planifiée sans navigateur. La session
de développement n'a pas accès à cet hébergement. La publication web n'active
aucune émission fiscale. Les essais doivent être faits en `pruebas` avant toute
activation de production.

Les taux de retenue et de paie se confirment dans leur configuration. Les dossiers
incomplets restent visibles et ne reçoivent pas de taux inventé. Une modification
de politique fournisseur prépare au plus 50 dossiers historiques en attente ; la
préparation groupée traite le reste, tandis que les validations individuelles
continuent à déclencher leur préparation automatiquement.

Voir [SRI](../modules/sri.md), [déploiement du moteur](../../services/sri/deploy/README.md),
[paie](../modules/hr.md), [comptabilité](../modules/accounting.md),
[Contacts](../contacts.md) et [portail B2B](../public-website.md).
