# GAMA — audit de sécurité et conformité équatorienne, 8 novembre 2026

**État : audit source réalisé, validation complète et mise en production non achevées.** Les correctifs web sont préparés et testés localement. Les corrections SQL sont des propositions non appliquées. Aucune conformité globale, absence de vulnérabilité ou correction en production n’est certifiée.

Périmètre : catalogue public GAMA de Coco ERP, Pages Functions, espace B2B, devis, demandes de commande invitées sans paiement, avis, sondages, administration du site et dépendances SQL/Auth/documents. Référence initiale : `8569f2e52c2e0fcdd5d036a73fb039522b49841a`, arbre initial propre. Profil standard, sans budget d’agents fixé. Deux vagues source : 12 unités, 11 revues sans candidat et une avec piste à valider ; quatre reconnaissances, cinq missions de chasse, deux critiques distinctes, deux vérifications indépendantes du candidat. Le critique final ne relève plus de frontière matérielle omise. Cela ne vaut pas validation d’exécution.

Le rapport réglementaire du 29 octobre a été relu comme contexte. Aucun registre machine compatible antérieur n’était disponible ; aucune ancienne vulnérabilité n’a été reprise sans examen. Les modules ERP sans lien avec le site, les comptes réels, les données de production, l’historique Git antérieur au checkout peu profond et les paramètres d’hébergement réels ne sont pas couverts.

## Résultat de sécurité

Les contrôles source sont substantiels : clé serveur séparée de la clé publique Supabase, origine vérifiée, IP injectée par le proxy, Turnstile lié au domaine et à l’action, corps HTTP et appels bornés, erreurs épurées, projections publiques, appartenance entreprise dérivée de l’identité courante, MFA applicable, prix calculés côté serveur, verrous/idempotence et instantanés de conditions sur commandes. Les textes sont échappés et les réponses d’une ancienne session invalidées.

**Aucune vulnérabilité n’est classée « confirmée » par cette passe**, faute de reproduction SQL du seul candidat retenu. Une piste source précise reste à valider ; elle a été relue par un vérificateur indépendant puis un second lecteur du dossier final. Aucun test de contournement n’a visé le site déployé.

| Piste à valider — sans sévérité attribuée | Frontière et source | Limite et correction préparée |
|---|---|---|
| Favoris B2B et photo historique sans restrictions du catalogue principal | `20261007190055_b2b_product_favorites.sql:50` accepte un produit actif ; `:34`/`:45` renvoient ses attributs et prix sans publication ni `commerce_product_allowed`. Le compte et son entreprise restent correctement vérifiés. | Un compte connaissant l’UUID d’un produit exclu pourrait obtenir son prix négocié. PGlite absent : aucun résultat SQL observé. Proposition `supabase/proposals/gama_b2b_catalog_visibility.sql`, test ajouté dans `tests/b2b-product-favorites-db.test.cjs`. |

Le catalogue B2B historique est effectivement redirigé vers la projection contrôlée ; il n’est pas une seconde faille. Les documents et commandes historiques restent accessibles selon leurs droits propres : le correctif ne les masque pas.

## Changements préparés

| Changement | Validation et état réel |
|---|---|
| CSP, protection contre l’encadrement, HSTS, politique de référent/permissions et `no-store` explicitement ajoutés aux réponses Functions, succès/erreurs/repli compris | Tests proxy et middleware réussis. Durcissement ; l’absence d’en-têtes seule n’est pas présentée comme vulnérabilité. Pas publié. |
| Prix négocié HT conservé et équivalent TTC ajouté dans le catalogue et l’espace B2B | Tests de calcul/rendu à IVA 0 %, 5 % et 15 % réussis. Les taux produits n’ont pas été requalifiés. Pas publié. |
| Interface capable de désactiver les demandes commerciales lorsque le serveur renvoie `collection_ready=false`, message clair et maintien des droits/réclamations | Test de compatibilité avec ancien bootstrap et état désactivé réussi. Le nouveau signal dépend de la proposition SQL. |
| Gestion d’un changement de version de politiques lors d’un devis : actualisation et retrait de l’accord précédent | Source revue ; parcours navigateur complet restant à exécuter. |
| Filtre SQL commun publication/produit actif/catalogue autorisé sur favoris et photo | Proposition uniquement ; test SQL préparé, non exécuté. |
| Modèle légal révisé : retour **ou échange**, quinze jours, règles de services et remboursement sans compensation imposée | JSON et SQL sous `docs/audits/proposals/gama-policies-2026-11-08.*`. Le modèle actif et les anciennes acceptations restent inchangés jusqu’à migration validée. |
| Garde SQL contre les nouveaux devis/commandes invités si identité et information préalable manquent, contrôle de version et instantané serveur du devis | Proposition `gama-intake-information-2026-11-08.sql`, fixture `storefront-intake-information-db.test.cjs`. Aucune valeur métier inventée. Les retries existants et le canal droits restent accessibles. Non exécuté. |
| CI spécifique étendue aux points d’entrée, schémas/configurations, conformité et nouveaux tests SQL | Préparée dans le workflow ; exécution CI non revendiquée. |

Les propositions SQL ne sont pas des migrations actives. Après validation isolée, générer des migrations avec le CLI Supabase et intégrer le SQL testé. Lors de l’activation du correctif favoris, adapter le premier test historique qui attend encore un favori inactif visible, et retirer l’application explicite de la proposition du second test. Ne pas appliquer deux fois le SQL.

## Matrice réglementaire et preuves de clôture

| Exigence | État dans le code et action restant nécessaire |
|---|---|
| LOPDP, information préalable (art. 12) | Champs identité/contact, finalités, droits et information publique présents. Leur remplissage réel n’est pas observé. La proposition bloque les nouveaux enregistrements commerciaux lorsque raison sociale, RUC, domicile, contact vie privée, conservation, destinataires ou procédure de droits sont absents. Un champ non vide ne prouve pas la suffisance juridique du texte. |
| Base légitime, consentement spécifique et minimisation | Précontractuel/contractuel distinct du marketing, aucun paiement par carte ni marketing automatique. Les sondages disposent de consentement et de schéma borné ; leur information préalable spécifique doit encore être complétée selon les finalités de chaque questionnaire. |
| Droits des personnes, délais et identité proportionnée | Canal gratuit, dossiers privés, vérification avant réponse, objectif opérationnel de quinze jours. Nommer un responsable et tester une demande fictive complète ; le suivi ne calcule pas tous les délais légaux. |
| Conservation, suppression et sauvegardes | Purge des dossiers clôturés configurable, preuve d’approbation et gel légal. Aucune durée n’a été inventée ni purge activée. Devis, commandes, avis, capabilities invités, journaux, archives et sauvegardes nécessitent un calendrier couvrant toutes les copies. |
| Prestataires, contrats et flux internationaux | Cloudflare/Supabase/Turnstile et autres prestataires effectifs à inventorier ; recueillir DPA, pays, rôles et garanties. Un hébergement étranger ne suffit pas à qualifier juridiquement tout flux de transfert : distinguer encargo et communication. |
| Incidents et SPDP | Documenter détection/confinement/évaluation, référent et notifications SISPDP selon la norme 2026-0040-R ; examiner les jalons de deux/cinq/trois jours selon rôle, destinataire, risque et calcul légal applicable. Aucun exercice opérationnel observé. |
| Désignation DPD et grande échelle | Analyse activité/MTGE à produire ; ne pas déduire une exemption du statut PME. Le contact DPD peut être renseigné dans les informations complémentaires lorsqu’applicable. |
| Consommateurs et contrat électronique | Prix public TTC déjà présent ; TTC secondaire B2B ajouté. Conditions versionnées, aucune réception de demande présentée comme achat/paiement. Proposition de texte alignée sur art. 45 LODC réformé : quinze jours, retour ou échange sous conditions. |
| Identité commerciale, livraison, garanties et remboursements | Raison sociale/RUC/adresses/contacts, couverture, coûts/délais et garanties réelles doivent être renseignés et approuvés. Ne pas publier une promesse de livraison ou garantie non justifiée. |
| IVA et SRI | Taux à valider SKU par SKU avec le comptable. Le site ne facture pas par son reçu de demande ; preuve d’émission/autorisation/transmission SRI et archivage sept ans requise. Depuis janvier 2026 transmission immédiate ; documentation SRI v2.34 juillet 2026. Examiner NAC-DGERCGC26-00000027 si Coco utilise un prestataire tiers entrant dans son champ. |
| Photos et information loyale | Les illustrations sont signalées, crédits présents. Confirmer licences/associations produit ; aucune licence nouvelle n’est supposée acquise par cet audit. |
| Publication effective et sécurité opérationnelle | Vérifier commit publié, migrations effectives, accès Data API/Storage, MFA réellement enrôlé, secrets/domaines Turnstile, chaîne IP Cloudflare, quotas/WAF, sauvegarde/restauration et dépendances/CVE. Aucun de ces paramètres n’est déduit d’un fichier de documentation. |

## Vérifications effectuées et limites

- **16 tests web réussis**, dont origine/clé/IP/antibot, limites de corps, redirections et erreurs, JSON initial sûr, protections des réponses, rendu progressif, prix TTC et information légale incomplète.
- **Compilation storefront réussie** dans une copie jetable. Un premier essai de copie intégrale a dépassé la limite par fichier à cause du pack Git ; le second exclut l’historique et ne copie que les entrées nécessaires.
- **297 empreintes de migrations appliquées vérifiées** ; aucune migration historique modifiée. 63 migrations nouvelles du dépôt existaient déjà au checkout.
- Tests SQL non exécutés : `@electric-sql/pglite` absent. Build ERP complet non exécuté : dépendances du projet absentes. Tests navigateur E2E non exécutés : dépendances de test du projet absentes. Les fichiers générés ERP ne sont pas modifiés manuellement.
- Les tests exécutés utilisent un environnement vide et autorisé, réseau externe désactivé, sources/outils en lecture seule, écriture en tmpfs privé 128 Mio, CPU 60 s, espace d’adressage 2 Gio, 64 processus, 16 Mio par fichier et échéance 90 s. Résultats minimaux capturés et promus par le parent, sans secret ni donnée de production.
- `findings.json` passe la validation JSON Schema standard. Les deux validateurs sémantiques fournis normalement par la compétence ne sont pas accessibles dans ce paquet cloud, ni à la racine ni sous `scripts/`. Leur réussite n’est pas revendiquée ; le statut de la passe reste `incomplete`.

Les limites d’exécution suivent la compétence [security-audit](skill://user/6ae3b17573688191b162ee7425fba918/security-audit/SKILL.md), notamment « Use only tools and dependencies already available locally. » Les paquets manquants n’ont pas été téléchargés pendant l’audit. Cette restriction ne justifie pas de qualifier les tests SQL préparés de réussis.

## Sources officielles

- [LOPDP, texte officiel](https://www.gob.ec/sites/default/files/regulations/2025-01/01%20Ley%20Org%C3%A1nica%20de%20Protecci%C3%B3n%20de%20Datos%20Personales.pdf), notamment art. 7–17 et 37–43.
- [LODC consolidée, ministère de la Production, réforme du 11 février 2022](https://www.produccion.gob.ec/wp-content/uploads/2025/03/LEY-ORGANICA-DE-DEFENSA-DEL-CONSUMIDOR_2022_02_11.pdf), notamment art. 9, 11, 17, 19 et 45 ; les anciennes copies à trois jours sont obsolètes.
- [Commerce électronique, consolidation ARCOTEL](https://www.arcotel.gob.ec/wp-content/uploads/2023/11/22_ley_de_comercio_electronico_firmas_y_mensajes_de_datos.pdf).
- [SPDP 2026-0040-R, violations de données](https://www.spdp.gob.ec/wp-content/uploads/2026/10/SPDP-SPD-2026-0040-r.pdf), [publication officielle RO 376](https://www.registroficial.gob.ec/suplemento-no-376/).
- [SPDP 2026-0004-R, communications/transferts](https://www.spdp.gob.ec/wp-content/uploads/2026/08/04.01.01-SPSP-SPD-2026-0004-R-Norma-general-de-transferencias-signed.pdf), [clauses contractuelles 2025-0006-R](https://www.spdp.gob.ec/wp-content/uploads/2025/12/06.01.01-SPDP-SPD-2025-0006-R-clausulas-para-contratos-en-Ecuador-signed_compressed.pdf), [DPD 2025-0028-R](https://www.spdp.gob.ec/wp-content/uploads/2025/12/028-R_compressed.pdf).
- [SRI : transmission immédiate 2026](https://www.sri.gob.ec/detalle-noticias?idnoticia=1239&marquesina=1), [documentation fiscale](https://www.sri.gob.ec/facturacion-electronica), [conservation sept ans](https://www.sri.gob.ec/detalle-noticias?idnoticia=1021&marquesina=1), [prestataires tiers, juillet 2026](https://www.sri.gob.ec/detalle-noticias?idnoticia=1318&marquesina=1).

La clôture globale nécessite les preuves opérationnelles et les validations juridique/comptable équatoriennes adaptées, ainsi que les tests et publications encore en attente. Aucun statut « vérifié » n’a été inscrit à leur place dans Coco.

## Livraison et autorisation de publication

Le premier téléversement vers le dépôt public a été bloqué par le contrôle automatique faute d’autorisation explicite. Le propriétaire a ensuite donné cette autorisation dans la conversation, pour publier les correctifs et le rapport détaillé sur `lisciandraj/Pro-manager-Gama` dans une **PR brouillon**.

Cette autorisation porte sur la branche de revue et son contenu public, dont les propositions SQL et la piste de sécurité non encore reproduite. Les réserves de validation restent inchangées : les propositions SQL ne sont pas des migrations actives, aucune clôture de conformité n’est revendiquée et aucun déploiement en production n’est autorisé par cette étape.
