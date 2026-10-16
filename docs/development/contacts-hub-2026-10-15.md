# Contacts hub — état courant

Le premier lot Contacts a été publié par la PR 164. La fiche à onglets donne accès à la synthèse, aux interlocuteurs et adresses, aux ventes/achats, à la finance, aux activités, aux documents, au compte cloud et au profil partagé selon les permissions. Les actifs sont chargés à la demande ; les services commerciaux, comptables et portail existants restent la source des données.

## Alignement du 16 octobre

Le [contrat d'alignement](contact-alignment.md) remplace l'ancienne limitation des coordonnées séparées par rôle. Clients, fournisseurs et prospects qui partagent explicitement une identité synchronisent maintenant leurs coordonnées communes côté serveur. Les personnes conservent leur identité et leurs coordonnées personnelles ; leur adresse peut être héritée ou indépendante. Notes, tarifs, conditions, crédit et droits portail restent propres à leur contexte.

L'accès courant reste Administration → Contacts. Le nom ouvre la fiche centrale ; « Modifier » ouvre le formulaire harmonisé et protégé par version. Dans la synthèse, une différence non résolue propose « Comparer et harmoniser ». Une association client/fournisseur reste une opération explicite administrateur ; aucune similarité de nom ou de coordonnées ne crée un lien automatique.

## Base et reconstruction

`20261015202048_coco_contacts_hub` est la migration du premier lot. L'[archive exacte](../../supabase/sql/applied/20261015202048_coco_contacts_hub.sql) et son manifeste restent inchangés. Une copie byte-identique existe désormais dans `supabase/migrations` pour reconstruire une base vide ; cette migration n'a pas été rejouée sur le projet installé. Le brouillon `supabase/pending/coco_contacts_hub.sql` reste réservé au test historique, qui restaure explicitement l'état antérieur.

Le déploiement de l'interface doit passer par les validations puis `deploy-coco-pages.yml`. Vérifier le job de publication et sa révision, pas seulement une compilation. Un retour du code ne doit pas supprimer les colonnes et données additives installées dans Supabase.

## Limites distinctes

L'alignement des coordonnées ne remplace pas l'ensemble du cahier des charges Odoo : les indicateurs multisites, l'annuaire des prospects CRM bruts, la propagation de toutes les consignes de site vers chaque instantané Ventes/TMS et les enrichissements fiscaux/import/fusion avancés restent des travaux séparés.
