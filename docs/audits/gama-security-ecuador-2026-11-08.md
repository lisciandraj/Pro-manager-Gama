# GAMA — sécurité et conformité équatorienne, livraison du 8 novembre 2026

Les corrections techniques de l’audit sont implémentées dans les sources et dans la migration additive `20261108163242_gama_website_security_compliance.sql`. Les anciennes propositions SQL sont retirées. Le rapport initial et ses limites d’observation restent disponibles dans [la capture d’audit initiale](../history/gama-security-ecuador-initial-2026-11-08.md) ; les fichiers machine sous `data/gama-security-2026-11-08/` décrivent cette capture, pas un état de production.

## Corrections livrées

| Écart | Comportement implémenté | Preuve de validation |
|---|---|---|
| Chemins parallèles favoris/photos B2B | Produit actif, publié, autorisé à l’entreprise et site ouvert exigés sur ajout, liste, IDs et photos. Les préférences devenues invisibles sont purgées sous verrou avant nouvel ajout, avec plafond de 500 conservé. | Fixture B2B : restrictions, retrait de publication, pause, photo autorisée, suppression, plafond et conservation OID/ACL. |
| Ancienne lecture de photos | La route lit `products.photo_data`, contrôle le format et conserve `photo` et `photo_is_illustrative`. | Comparaison de l’image fictive exacte ; la table `product_photos` supprimée n’est plus consultée. |
| Information préalable incomplète | Nouveaux devis et commandes invités refusés si identité, RUC, domicile, contact confidentialité, conservation, destinataires ou procédure de droits manquent. L’interface masque les champs commerciaux et explique la situation. | Tests SQL et navigateur, avec catalogue et canal droits/réclamations toujours accessibles. |
| Version et preuve d’information | Version courante exigée à la création, instantané complet conservé sur le devis ; checkout transmet la version contrôlée. Les retries existants renvoient leur résultat et les anciens instantanés ne sont pas réécrits. | Test d’upgrade, retry avant/après changement de politiques, contrat du checkout et absence de preuve rétroactive fabriquée. |
| Limites de demandes partagées | Vérification et insertion sérialisées pour les compteurs communs e-mail/jour, en complément des verrous existants. | Contrôle du chemin transactionnel et tests de quotas existants ; aucun stress de production. |
| Informations consommateurs | Retour ou échange sous quinze jours selon conditions légales ; règles des services et remboursement sans compensation imposée. Prix HT négocié conservé avec équivalent TTC par taux produit. | Modèles SQL/JSON synchronisés ; calculs IVA 0/5/15 et parcours catalogue/B2B. |
| Confidentialité des sondages | Notice courante, version, identité et finalité indiquée par le questionnaire visibles avant saisie. Si la notice est indisponible, aucun formulaire n’est affiché ; réessai localisé. Le jeton et les réponses ne sont pas transmis à la lecture des politiques. | Huit scénarios Chromium, dont ES/FR/EN, notice échappée, panne/réessai et réponse déjà enregistrée. |
| Protections navigateur | En-têtes CSP, anti-encadrement, HSTS, référent/permissions et no-store sur réponses Functions, erreurs et replis. | Tests du proxy et middleware. |
| Dépendance de développement | Vite épinglé à 6.4.5, correction de l’avis GHSA-8g5g-mxqh-grgj concernant `server.fs.deny`. | Audit npm après mise à jour : aucune vulnérabilité connue signalée. |

## Validation

Les tests SQL ciblés, les builds ERP et catalogue, les contrôles de génération, sources, types, documentation, vendors, migrations et budget de démarrage réussissent. Les 79 tests navigateur existants catalogue/B2B et neuf contrôles complémentaires confidentialité/collecte réussissent. Les résultats de la suite globale et des contrôles CI sont consignés dans la PR de livraison.

Les bases de tests sont jetables et contiennent uniquement des comptes et données fictifs. Les deux tests de concurrence qui exigent un PostgreSQL distinct conservent leur condition d’exécution ; PGlite ne remplace pas une preuve multi-session PostgreSQL.

## Activation et informations métier

La mise en production suit les [instructions du site public](../public-website.md) et la [publication compilée](../development/pages-publication.md). La migration, les actifs ERP et le catalogue Cloudflare ont des chemins de déploiement distincts. Une PR à jour n’établit pas qu’ils sont déployés.

Avant d’activer la nouvelle collecte, compléter dans Coco **Site web → Site public → Informations légales** les valeurs réelles : raison sociale, RUC, domicile, contact de confidentialité surveillé, durées par finalité, destinataires/flux et procédure de droits. La migration ne modifie ni ces valeurs, ni les taux fiscaux des produits, ni les règles de purge approuvées. Si ces informations manquent, les nouvelles demandes commerciales restent bloquées ; les droits et réclamations restent accessibles.

Les preuves organisationnelles restent requises : contrats/DPA et pays des prestataires, calendrier complet des données/sauvegardes, exercice des droits et incidents/SISPDP, analyse DPD/MTGE, conditions de livraison/garantie/remboursement, licences des photos et validation comptable IVA/SRI. Le logiciel ne certifie pas leur exécution.

## Références

- [LOPDP, texte officiel](https://www.gob.ec/sites/default/files/regulations/2025-01/01%20Ley%20Org%C3%A1nica%20de%20Protecci%C3%B3n%20de%20Datos%20Personales.pdf).
- [LODC consolidée, ministère de la Production](https://www.produccion.gob.ec/wp-content/uploads/2025/03/LEY-ORGANICA-DE-DEFENSA-DEL-CONSUMIDOR_2022_02_11.pdf), notamment article 45.
- [SPDP, norme de notification des violations 2026-0040-R](https://www.spdp.gob.ec/wp-content/uploads/2026/10/SPDP-SPD-2026-0040-r.pdf).
- [SRI, facturation électronique](https://www.sri.gob.ec/facturacion-electronica).
- [Avis Vite corrigé](https://github.com/advisories/GHSA-8g5g-mxqh-grgj).
