# Corrections reproduites avant publication

| ID | Gravité | Reproduction | Correction et preuve |
| --- | --- | --- | --- |
| TMS-PRO-01 | S2 | Fonction SQL avec variables et alias de même nom | Noms du profil distincts et résolution explicite ; tests serveur |
| TMS-PRO-02 | S2 | Équilibrage consommant un véhicule qualifié avant une livraison exigeant cette qualification | Priorité aux livraisons contraintes ; cas à deux conducteurs |
| TMS-PRO-03 | S2 | Avis public routé vers un schéma non accessible à anon | Implémentation dans private_tracking avec seule façade publique autorisée ; test anonyme et expiration |
| TMS-PRO-04 | S2 | Horaire vérifié ignorant les créneaux supplémentaires | Même résolution de créneau que le planner ; attente et départ réel testés |
| TMS-PRO-05 | S2 | En restauration neuve, la politique d’historique reste liée à l’ancienne fonction renommée et refuse une lecture authentifiée des nouvelles règles | Migration additive de liaison des politiques ; lecture autorisée au dispatch et refusée aux conducteurs |
| TMS-PRO-06 | S3 | Un navigateur anglais changeait la langue d’anciens liens de suivi sans paramètre de langue | Espagnol historique par défaut ; FR/EN explicites dans le lien, couverts par tests |

Les limites produit sont dans features.csv ; elles ne sont pas présentées comme des défauts corrigés. La comparaison graphique à un écran authentifié d'OptimoRoute n'a pas été réalisée.
