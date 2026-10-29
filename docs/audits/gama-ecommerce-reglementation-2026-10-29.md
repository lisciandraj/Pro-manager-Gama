# GAMA — audit réglementaire du commerce électronique en Équateur

Date de recherche : **29 octobre 2026**. Périmètre : catalogue, achat invité, comptes professionnels, approbations, avis, paiement, contact et données personnelles. Sources : textes et communications des autorités équatoriennes cités ci-dessous. Ce document établit les exigences et les preuves à réunir ; il ne constate pas que les contrôles techniques, les contrats ou les pratiques internes de GAMA sont déjà conformes.

## Constats techniques de GAMA et limites de livraison

Inspection des réglages réels le 29 octobre 2026 : boutique `https://gama-coco.pages.dev/`, sans domaine commercial rattaché ; identité légale, RUC du site, contact de confidentialité et WhatsApp non renseignés. Le numéro fiscal de l’ERP comporte onze chiffres et ne constitue donc pas un RUC vérifié. Le propriétaire prévoit de renseigner ces éléments dans Coco. Aucun prestataire de paiement n’a été choisi.

Parmi les produits actifs, 152 portent le taux 0 %, un le taux 5 % et 1 632 le taux 15 %. Ces valeurs constatées ne sont pas une validation fiscale des références. La base Supabase est hébergée en Irlande. Aucun widget Turnstile n’était configuré au début de l’intervention.

Le code livré prépare : prix TTC publics et HT négociés B2B ; récapitulatif d’IVA serveur ; demande invitée avec facturation obligatoire, revue et reçu privé ; contrôle antibot serveur ; catalogues autorisés par entreprise ; demandeurs/approbateurs par niveaux avec remise à zéro lors d’une modification ; avis réservés aux commandes confirmées ; historique et copie à revalider ; information vie privée, retours et stockage. Les photos de recherche et le bouton WhatsApp conditionnel existaient déjà et sont conservés.

**Limites explicites** : une demande invitée crée un devis à confirmer, sans débit, réservation ni facture fiscale. Le paiement réel reste indisponible. Le reçu invité est accessible dans l’onglet qui l’a créé ; aucune récupération par e-mail n’est annoncée. La politique de cookies correspond à l’absence actuelle de traceurs facultatifs ; elle ne dispense pas d’implémenter un véritable blocage/opt-in si de tels outils sont ajoutés. La rédaction d’une politique ne prouve ni contrats de traitement signés, ni purge/archivage opérationnels, ni exercice effectif des droits. L’état du déploiement doit être vérifié séparément du code et des tests.

## Décisions qui changent l'implémentation

1. **IVA générale : 15 %**, maintenue tant qu'un nouveau décret ne la modifie pas. La circulaire SRI NAC-DGECCGC25-00000006 du 26 décembre 2025 confirme cette continuité. La page explicative générique du SRI mentionnant encore 13 % ne suffit pas pour paramétrer 2026. [S1]
2. **TVA par produit** : le papier bond et les livres figurent dans les biens à taux zéro ; ne pas imposer 15 % à toute la papeterie. Chaque référence doit conserver sa qualification fiscale validée. Le taux zéro, l'exonération et l'opération hors champ sont des traitements distincts. [S2]
3. **Retours : quinze jours**, et non l'ancienne règle de trois jours. L'article 45 LODC, remplacé le 11 février 2022, prévoit un *término de quince días* après réception, sous conditions de nature et d'état. La règle porte sur les achats par tout moyen. Les conditions commerciales ne doivent pas remplacer le remboursement dû par un bon d'achat. [S3]
4. **Compte B2B ≠ exemption consommateur ou fiscale**. Une personne morale achetant pour son usage final peut relever de la LODC. Les prix négociés peuvent être présentés HT, avec une indication explicite ; le coût final et les taxes doivent rester accessibles avant l'engagement. Par prudence, afficher un équivalent TTC secondaire dans le catalogue B2B et le détail HT/IVA/TTC au panier. [S3]
5. **Achat invité ≠ facturation anonyme**. Collecter les données nécessaires sans créer de compte. Une confirmation de commande ou un PDF interne ne remplace pas un document fiscal valable. Depuis le 1er janvier 2026, les documents électroniques doivent être transmis immédiatement au SRI. [S4]
6. **La conformité ne peut pas être établie par l'ajout de pages légales seul**. Il faut également les données légales exactes de GAMA, les modalités commerciales effectives, la qualification fiscale du catalogue, les contrats des prestataires et des preuves de fonctionnement.

## Matrice de conformité

Les mesures ci-dessous sont les contrôles proposés pour GAMA. « À prouver » indique une preuve opérationnelle manquante dans cette recherche réglementaire ; cela ne préjuge pas de ce qui existe déjà en production.

| Domaine | Exigence et base | Mesure concrète proposée | Preuve à obtenir |
|---|---|---|---|
| Identité du vendeur | Informations commerciales fiables ; identité du responsable des données. LODC art. 17, LOPDP art. 12 [S3, S7] | Pied de page et mentions : raison sociale exacte, nom commercial, RUC, domicile, contact réel ; désigner le responsable du traitement | RUC actuel, représentant, adresse légale et adresse de retours validés |
| Prix public | Prix final visible, taxes et frais ; espagnol et monnaie locale. LODC art. 9, 10, 19 [S3] | TTC dominant sur résultats, cartes, fiche et panier ; afficher USD, unités, conditionnements et frais de livraison avant confirmer | Captures invité, panier mixte 0/15 %, variations livraison |
| Tarifs B2B | Même fiscalité, conditions négociées explicites [S1–S3] | Prix lié à l'entreprise côté serveur ; libellé « sin IVA » ; aperçu TTC et récapitulatif final ; expiration des accords | Tests client A/B, session expirée, accord périmé, prix envoyé falsifié |
| Classification IVA | 15 % général, exceptions selon bien et régime [S1, S2] | Taux et code fiscal par référence, source/date de validation, historique ; aucune déduction automatique par simple mot-clé | Validation du comptable, notamment papier, livres, produits médicaux/entretien s'ils sont vendus |
| Facturation invitée | Identification et facture selon régime du vendeur et transaction [S4, S5] | Type/numéro d'identification, nom/raison sociale ; adresse de facturation, courriel de remise et livraison ; pas de mot de passe imposé | RUC/régime de GAMA, XML/RIDE test, traitement d'une adresse et d'un passeport étrangers |
| Validation RUC | Le SRI précise que certaines catégories de RUC n'ont pas d'algorithme spécifique imposé [S5] | Ne pas rejeter un RUC de société avec un checksum universel ; validation de format et vérification officielle adaptée | Cas réels autorisés par le comptable, sans les exposer dans les tests publics |
| Facture électronique | Signature, transmission et autorisation adaptées ; pas de valeur fiscale en environnement d'essai [S4, S5] | Relier commande/paiement à la facture ; journal d'envoi, rejet et nouvelle tentative ; accès sécurisé XML/RIDE | Configuration SRI réelle, certificat, prestataire, test complet de production autorisé |
| Correction des ventes | Restrictions depuis 2026 pour les factures « consumidor final » [S6] | Privilégier la facture nominative demandée ; faire valider le traitement comptable des retours ; distinguer remboursement et correction fiscale | Procédure approuvée par le comptable, cas d'échec/anulation/remboursement |
| Livraison | Respect des engagements et information suffisante. LODC art. 18, 21 [S3] | Territoires desservis, coût et date/fenêtre convenus ; justificatif conservable ; notification de retard avec solution | Grille de livraison, conditions d'indisponibilité et procédure d'incident |
| Retours/garanties | Délai de retour actualisé ; garantie des biens durables. LODC art. 11, 20, 45 [S3] | Politique espagnole, formulaire lié à la commande, canal invité, traitement distinct retour/produit défectueux ; durée/lieu de garantie par produit | Calendrier de calcul juridique validé, adresse et opérateur de retours, modalités réelles de remboursement |
| Contrat électronique | Information accessible, accord prouvable, conservation ; ouvrir un message n'est pas accepter. Loi commerce électronique art. 3, 6–8, 45–50 [S8] | Écran de revue, correction du panier, acceptation explicite des CGV versionnées, reçu téléchargeable et numéro unique | Version des conditions, horodatage et contenu accepté, commande dupliquée non confirmée automatiquement |
| Circuit B2B | Contrat et habilitations prouvables ; minimiser l'accès aux données [S7, S8] | Demandeur/approbateur rattachés explicitement à une entreprise ; plusieurs demandeurs par approbateur ; panier versionné ; modification après validation exige nouvelle validation | Mandat client, matrice de droits, tests de franchissement d'entreprise et double validation |
| Avis vérifiés | Information/publicité loyales ; données du contributeur protégées [S3, S7] | Éligibilité par ligne réellement achetée, contrôle serveur ; ne publier ni adresse ni numéro de commande ; pseudonyme ; modération factuelle documentée | Tests achat annulé, avis d'un autre client, suppression/édition, faux statut d'achat |
| Recherche/images | Descriptions et représentations fidèles [S3] | Photo rattachée au bon SKU, référence, unité, stock annoncé fiable, prix cohérent ; signaler explicitement une image illustrative | Échantillon produit/image, droits d'usage des photos, filtres de catalogue B2B |
| Paiement | Prestataire autorisé pour son service ; conditions contractuelles et sécurité [S15] | Choisir un PSP adapté à l'Équateur, paiement hébergé ; confirmation côté serveur ; montant calculé depuis la commande validée ; pas de stockage des données de carte | Contrat marchand, prestataire exact au catastro BCE, clés et webhook, remboursement et paiement dupliqué testés |
| Contact et antibot | Mesures de sécurité proportionnées [S7, S11] | Limitation de débit, validation serveur, protection antibot ; prévenir le contournement par appel direct au backend ; limiter les journaux IP | Tests jeton absent/rejoué, origine étrangère, quotas, panne prestataire ; analyse d'intérêt légitime si utilisée |
| WhatsApp | Transparence sur le destinataire et le traitement [S7, S12] | Numéro d'entreprise vérifié, lien déclenché par clic ; avertissement de sortie ; aucun numéro de commande secret ou donnée personnelle injecté dans l'URL | Numéro, accès des employés, politique Meta/WhatsApp et règles de conservation internes |
| Historique/recommande | Confidentialité et nouveau consentement contractuel [S7, S8] | Voir seulement les commandes autorisées ; copier en brouillon ; recalculer prix/taxes/disponibilité ; rejouer les approbations | Tests interentreprises, ancien prix, produit retiré, approbateur révoqué |

### Données personnelles : obligations et contrôles dédiés

La LOPDP impose une base légitime, une information préalable, la minimisation, la sécurité et une conservation justifiée. L'exécution de la commande et les obligations fiscales n'exigent pas un consentement marketing global. Les droits comprennent notamment accès, rectification, suppression, opposition et portabilité ; plusieurs demandes doivent être traitées sous quinze jours. [S7, S9]

| Obligation/base | Contrôle proposé pour GAMA | Pièces manquantes pour conclure |
|---|---|---|
| Information préalable, LOPDP art. 12 [S7] | Avis court auprès de chaque formulaire et politique détaillée : identité/contact, finalités et bases, catégories, conservation, destinataires, droits, réclamations, décisions automatisées éventuelles | Identité exacte, adresse du responsable, courriel réellement surveillé, traitements réellement déployés |
| Consentement libre et spécifique, LOPDP art. 8 [S7] | Séparer CGV, information vie privée, publicité, cookies facultatifs ; aucune case promotionnelle précochée | Textes définitifs, preuve de choix, parcours de retrait |
| Cookies et traceurs [S7, S10] | Inventorier cookies, localStorage, pixels et appels tiers ; laisser les éléments nécessaires au service ; bloquer les traceurs facultatifs avant opt-in ; boutons accepter/refuser/personnaliser simples ; modifier ensuite le choix | Capture réseau vierge/refus/acceptation/retrait, inventaire avec fournisseur/finalité/durée |
| Intérêt légitime [S11] | Pour antifraude/journaux ou autre usage retenu : évaluation préalable de nécessité et de proportionnalité, accessible et revue ; ne pas utiliser cette mention comme dispense générale | Évaluation en espagnol, responsable, version et date de revue |
| Exercice des droits [S9] | Canal gratuit, vérification proportionnée de l'identité, suivi d'échéance, export sûr, réponse motivée si conservation légale ; ne pas effacer une facture obligatoire pour supprimer un compte | Responsable opérationnel et essai complet d'une demande fictive |
| Rétention fiscale [S16] | Conserver les pièces fiscales au moins sept ans ; accès d'archive restreint, restauration testée ; séparer les données actives et l'archive | Plan d'archivage, preuve de sauvegarde et restauration |
| Suppression/limitation [S17] | Durées par finalité pour brouillons, contacts, journaux, avis ; purge automatisée et contrôle des sauvegardes ; pseudonymiser n'est pas anonymiser | Calendrier approuvé et journal d'exécution des purges |
| Contrats de traitement [S13] | Accords adaptés avec hébergement, base de données, e-mail, paiement, antibot et intervenants ; clauses précises sur finalités, sécurité, incident, restitution/suppression | Contrats/DPA réels, rôles, sous-traitants ultérieurs, accès support |
| Communications et international [S12] | Cartographier chaque flux ; qualifier « encargado » ou responsable indépendant ; évaluer garanties lorsque le régime de transfert s'applique | Pays, rôle contractuel, garanties et documentation des transferts ; minimum trois ans pour les pièces de justification prévues à l'art. 4 |
| Incident [S14, S7] | Procédure avec détection, confinement, évaluation du risque, preuve et notification via SISPDP ; prévoir ARCOTEL selon art. 43 ; modèle de message client | Référent disponible, contacts, exercice de crise et preuve du canal SISPDP |
| DPD et grande échelle [S18, S19] | Documenter l'analyse de désignation et le modèle MTGE ; ne pas déduire « aucune obligation » du seul statut PME | Nombre de titulaires, catégories, fréquence, durée active, géographie ; traitements enfants/profilage/technologies fournis à autrui |
| Gouvernance [S7, S19] | Registre des traitements, risques, habilitations, formations ; examiner les obligations d'enregistrement SPDP applicables | Inventaire signé, revue des accès, responsable et situation du registre national |

**Cookies : portée de la conclusion.** Aucun régime autonome « ePrivacy européen » n'est supposé applicable à GAMA. Les contrôles proposés traduisent la LOPDP pour les technologies traitant des données personnelles. La politique cookies de la SPDP est un exemple institutionnel, pas un texte créant à elle seule une obligation générale. De même, la résolution SPDP-SPDP-2024-0019-R est la politique de la SPDP ; ne pas la présenter comme un modèle réglementaire imposé à toutes les entreprises.

**International : distinction 2026.** L'article 23 de la résolution SPDP-SPD-2026-0004-R distingue la sous-traitance (*encargo*) d'une communication/transfert ; l'article 24 traite l'usage de clauses modèles dans cet encargo comme bonne pratique. Un serveur en Irlande ne permet donc pas, à lui seul, de qualifier juridiquement tous les flux. Les rôles et les contrats effectifs restent déterminants. [S12]

**Incidents : délais à opérationnaliser.** Sous-traitant vers responsable : au plus deux jours ; responsable vers SPDP : cinq jours selon les textes, dès que possible ; personnes affectées : trois jours lorsque les conditions de risque sont réunies. Conserver la formulation espagnole *término/plazo* dans la procédure validée pour le calcul des délais. Les critères, exceptions et canaux doivent être appréciés sur l'incident réel. [S14, S7]

**DPD : analyse, pas réponse automatique.** La résolution 2025-0028 comporte des cas supplémentaires de nomination, notamment certaines activités de profilage marketing et de services technologiques. La résolution 2026-0005 utilise six composantes et un seuil de six points, avec des cas de qualification directe. Le score et les activités exactes de GAMA restent à documenter. [S18, S19]

## Informations à obtenir de GAMA avant de déclarer les écarts fermés

- Raison sociale, RUC/régime fiscal, représentant, adresses légales et de retours, téléphone, courriel de service et de protection des données.
- Domaine final de la boutique et distinction avec toute autre boutique encore publiée ; responsable des DNS et des contenus commerciaux.
- Tarif de livraison, territoires, délai annoncé, garanties par famille, procédure et moyen de remboursement.
- Matrice fiscale des produits validée par le comptable ; preuve de facturation SRI en production et de transmission/archivage.
- Prestataire de paiement réellement contracté, compte marchand, services autorisés et conditions de chargeback.
- Autorités d'approbation désignées par chaque client professionnel ; règles de modification et de délégation.
- Liste des prestataires, DPA/contrats et pays de traitement ; inventaire des cookies et outils de mesure.
- Responsable interne des demandes de droits et incidents ; analyse DPD/MTGE ; durées de conservation approuvées.

Les formalités générales de l'entreprise, les autorisations municipales d'exploitation, les normes de sécurité/étiquetage des produits et la comptabilité doivent faire l'objet de vérifications propres à l'activité. Le présent périmètre ne permet pas de certifier toutes les obligations de GAMA.

## Critères de clôture proposés

Le site peut être déclaré prêt sur le périmètre vérifié lorsque chaque exigence possède un propriétaire et une preuve : conditions réelles approuvées, calculs comparés à la facturation, tests des droits et du cloisonnement, paiement et remboursement vérifiés, absence de traceurs facultatifs avant consentement, dossier de sous-traitance et procédures internes opérationnelles. Un statut « document rédigé » ne vaut pas « obligation exécutée ». La validation juridique équatorienne des textes finaux et la validation comptable de l'IVA/SRI restent les preuves professionnelles adaptées pour clôturer ces points.

## Sources officielles consultées

- **S1** — SRI, circulaire NAC-DGECCGC25-00000006, 26 décembre 2025, maintien IVA 15 % : https://www.sri.gob.ec/o/sri-portlet-biblioteca-alfresco-internet/descargar?id=236482f4-6125-42fd-b073-62c99d08233d&nombre=NAC-DGECCGC25-00000006.pdf ; publication : https://www.registroficial.gob.ec/suplemento-no-192/
- **S2** — SRI, liste des biens/services à taux zéro, notamment papier bond/livres : https://www.sri.gob.ec/o/sri-portlet-biblioteca-alfresco-internet/descargar/38e837fe-49b1-460c-983e-efd39fd04303/Bienes%20y%20servicios%20gravados%20con%20tarifa%20cero%20porciento%20del%20IVA.pdf . Liste indicative ancienne : vérifier la qualification actuelle de chaque SKU, ne pas en faire une liste exhaustive 2026.
- **S3** — Ministère de la Production, LODC consolidée avec réforme du 11 février 2022 : https://www.produccion.gob.ec/wp-content/uploads/2025/03/LEY-ORGANICA-DE-DEFENSA-DEL-CONSUMIDOR_2022_02_11.pdf . Réforme originale à l'Assemblée : https://www.asambleanacional.gob.ec/es/system/files/ro-1-supl-11-02-2022.pdf . L'ancienne copie WIPO indiquant trois jours n'est pas la version pertinente de l'article 45.
- **S4** — SRI, transmission immédiate dès 2026, 30 décembre 2025 : https://www.sri.gob.ec/detalle-noticias?idnoticia=1239&marquesina=1
- **S5** — SRI, facturation électronique, documentation technique version 2.34 de juillet 2026 et avertissement validation RUC : https://www.sri.gob.ec/facturacion-electronica
- **S6** — SRI, NAC-DGERCGC25-00000014 : https://www.sri.gob.ec/o/sri-portlet-biblioteca-alfresco-internet/descargar?id=137046a6-787c-47fb-a2d7-176595d292dc&nombre=NAC-DGERCGC25-00000014.pdf ; réforme NAC-DGERCGC25-00000017 : https://www.sri.gob.ec/o/sri-portlet-biblioteca-alfresco-internet/descargar?id=e98fc8a6-299e-4ea9-8de7-2f6c70dbb4f5&nombre=NAC-DGERCGC25-00000017.pdf
- **S7** — LOPDP, publication officielle disponible via portail gouvernemental : https://www.gob.ec/sites/default/files/regulations/2025-01/01%20Ley%20Org%C3%A1nica%20de%20Protecci%C3%B3n%20de%20Datos%20Personales.pdf ; cadre de référence SPDP : https://www.spdp.gob.ec/marco-normativo/ ; règlement général : https://www.spdp.gob.ec/wp-content/uploads/2026/09/03-Reglamento-General-de-la-Ley-Organica-de-Proteccion-de-Datos-Personales-2023.pdf
- **S8** — ARCOTEL, loi commerce électronique consolidée au 7 février 2023 : https://www.arcotel.gob.ec/wp-content/uploads/2023/11/22_ley_de_comercio_electronico_firmas_y_mensajes_de_datos.pdf
- **S9** — Direction nationale des registres publics, articles 13–17 LOPDP : https://www.registrospublicos.gob.ec/base-legal-ejercicio-de-los-derechos-de-proteccion-de-datos-personales/
- **S10** — SPDP, politique cookies institutionnelle (exemple, pas norme générale) : https://www.spdp.gob.ec/politica-de-cookies/
- **S11** — SPDP-SPD-2025-0041-R, intérêt légitime : https://www.spdp.gob.ec/wp-content/uploads/2025/12/41.01.01-SPSP-SPD-2025-0041-R-Normativa-general-para-la-aplicacion-del-interes-legitimo-y-su-anexo_compressed.pdf
- **S12** — SPDP-SPD-2026-0004-R, communications/transferts : https://www.spdp.gob.ec/wp-content/uploads/2026/08/04.01.01-SPSP-SPD-2026-0004-R-Norma-general-de-transferencias-signed.pdf
- **S13** — SPDP-SPD-2025-0006-R, clauses contractuelles : https://www.spdp.gob.ec/wp-content/uploads/2025/12/06.01.01-SPDP-SPD-2025-0006-R-clausulas-para-contratos-en-Ecuador-signed_compressed.pdf
- **S14** — SPDP-SPD-2026-0040-R, notifications de violations, 9 septembre 2026 : https://www.spdp.gob.ec/wp-content/uploads/2026/10/SPDP-SPD-2026-0040-r.pdf
- **S15** — BCE, système auxiliaire de paiements et catalogue des autorisations : https://www.bce.fin.ec/sistema-de-pagos/sistema-auxiliar-de-pagos/
- **S16** — SRI, conservation des pièces électroniques sept ans, 28 mars 2024 : https://www.sri.gob.ec/detalle-noticias?idnoticia=1021&marquesina=1
- **S17** — SPDP-SPD-2025-0030-R, pseudonymisation/anonymisation/blocage/suppression : https://www.spdp.gob.ec/wp-content/uploads/2025/12/0030-R_compressed.pdf
- **S18** — SPDP-SPD-2025-0028-R, délégué : https://www.spdp.gob.ec/wp-content/uploads/2025/12/028-R_compressed.pdf
- **S19** — SPDP-SPD-2026-0005-R, grande échelle : https://www.spdp.gob.ec/wp-content/uploads/2026/08/Resolucion0005.pdf

Recherche non retenue comme preuve primaire : une consolidation commerciale a signalé une date de modification LRTI au 19 octobre 2026, mais son renvoi ne suffisait pas à établir la réforme applicable. Aucune modification de taux générale postérieure à S1 n'a été identifiée dans les sources officielles consultées. Une confirmation fiscale SKU par SKU reste nécessaire ; aucun catalogue existant n'a été requalifié par cette recherche.

## Mise en œuvre du complément demandé le 29 octobre 2026

Les contrôles logiciels complémentaires sont décrits dans
[Site public — Conformité, informations légales et WhatsApp](../public-website.md#conformité-informations-légales-et-whatsapp--29-octobre-2026).
Ils ajoutent les champs publics manquants, le canal de demandes de droits et de
retours, leur suivi privé et leurs preuves, les versions complètes des conditions
acceptées (invité et acceptation de devis B2B), le retrait/modération des avis et
la purge paramétrable des seules demandes clôturées.

Le registre de conformité permet de documenter les écarts organisationnels,
contractuels, fiscaux et opérationnels. Il n'invente pas les preuves pour les
clôturer. La durée de conservation automatique reste à valider avant activation.
Le calendrier juridique des retours et incidents, les contrats des prestataires,
la qualification IVA du catalogue, la facturation SRI effective et le paiement
réel restent à démontrer par les responsables concernés. Les champs légaux et
WhatsApp sont modifiables dans Coco sans déploiement de code.
