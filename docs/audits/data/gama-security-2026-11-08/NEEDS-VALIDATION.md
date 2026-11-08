# Validations encore nécessaires

La passe reste incomplète : tests SQL, tests navigateur, build ERP complet et validateurs sémantiques de la compétence non disponibles. La production n’a pas été sondée ni modifiée.

## Candidat sécurité unique

Fingerprint : `b2b-product-favorites:missing-publication-and-catalogue-scope`.

Entrée : façade authenticated `public.gama_b2b_product_favorites`, migration `20261007190055_b2b_product_favorites.sql:69`. L’entreprise est correctement dérivée à `:18`. Ajout à `:50` et lecture à `:34`/`:45` sans les filtres de publication/restriction appliqués au catalogue principal par `20261029201003_gama_ecommerce_workflows.sql:289`. La photo historique à `20261005014142_ec_b2b_customer_portal.sql:114` présente le même écart de filtre.

Bloqueurs : PGlite absent pour la reproduction isolée ; définitions et paramètres réellement déployés non observés. Aucune sévérité ni exposition de production affirmée.

Plan local : compte cliente confirmé, appartenance active, entreprise restreinte et deux produits fictifs A autorisé et B exclu. Vérifier le refus de B dans le catalogue principal puis la réponse des favoris/IDs/photo. Appliquer la proposition dans cette même base isolée et vérifier refus d’ajout/photo B, absence de B dans les listes, retrait toujours possible et prix A intact. Répéter avec dépublication d’un favori existant. Fixture : `tests/b2b-product-favorites-db.test.cjs`, second test.

Plan propriétaire : relever les définitions effectives, migrations et configuration de catalogue, puis comparer au correctif validé. Aucune requête de contournement au site réel n’est nécessaire.

## Corrections SQL et déploiement

Valider les propositions B2B, modèles légaux et garde d’information avec les fixtures préparées. Générer ensuite les migrations avec le CLI Supabase, adapter les tests historiques à la nouvelle règle, exécuter la suite requise et déployer séparément SQL, ERP et Cloudflare. Garder les droits/réclamations accessibles. Compléter les champs légaux avant activation de la garde.

## Preuves réglementaires et organisationnelles

Le propriétaire doit fournir les informations et preuves listées dans la matrice du rapport : identité/RUC/contacts, durées par finalité et sauvegardes, prestataires/contrats/pays, responsabilités et exercice de droits/incidents, analyse DPD/MTGE, conditions commerciales et licences, qualification IVA et fonctionnement SRI effectif. Un document rédigé ou une case remplie n’est pas une preuve d’exécution.
