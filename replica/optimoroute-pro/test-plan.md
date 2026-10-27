# Vérification

F01-H1 : tests existants TMS, préparation, chargement et réception. Aucun mouvement de stock en double après planification ou rejeu.

F02-H1 : aperçu immuable puis application sur deux jours, livraison flexible reportée au jour autorisé. F02-E1 : changement des règles après aperçu → TMS_PLAN_STALE. F02-E2 : même clé et même contenu → même résultat ; contenu différent → conflit. F02-N1 : périodes invalides et dépassement de 35 jours refusés.

F03-H1 : conducteur et véhicule compatibles, premier créneau inaccessible et attente jusqu'au deuxième. F03-E1 : compétences absentes → livraison non affectée. F03-E2 : version ancienne refusée. F03-N1 : affectation manuelle incompatible refusée ; perte de compétence après planning bloque le départ. L'horaire vérifié attend le créneau puis permet le départ groupé standard.

F04-H1 : après départ réel, seul le chauffeur affecté écrit une position ; dispatch voit la trace et ETA. F04-E1 : rejeu identique conservé ; clé avec coordonnées différentes refusée. F04-N1 : latitude hors limites et date future refusées ; autre conducteur et lecture directe des tables refusés. Navigateur : zéro écriture avant action explicite ; arrêt au changement de compte.

F05-H1 : réception standard puis avis 5/5 avec jeton. F05-E1 : un second appel n'écrase pas l'avis. F05-N1 : avant livraison ou avec jeton invalide/expiré → refus. Projection publique sans nom client ni GPS.

F06-H1 : agrégats et note disponibles au dispatch ; CSV et GPX téléchargés. F06-N1 : profil chauffeur/anon refusés. F06-E1 : cellule commençant par = neutralisée, caractères XML échappés.

S02/S04/S05 : navigateur 1440 px/390 px, absence d'erreurs de page et HTTP 5xx, contrôle axe du calendrier, formulaire clavier et contraintes de largeur. Captures sauvegardées dans clone-screens/.

Migration : restauration intégrale en base isolée ; essai d'application après historique peuplé et conservation de l'implémentation précédente d'autorisation des historiques. Aucune fixture ni faux départ n'est injecté en production.


F03-H2 : définir deux dimensions, capacités par véhicule et charges par livraison ; le cumul répartit les livraisons sur deux véhicules. F03-N2 : valeur négative, type texte, quatrième décimale, clé inconnue, doublon de clé, coordonnées invalides ou lieu de fin manquant sont refusés.

F03-E3 : une charge absente reste inconnue, une charge zéro est explicite. La livraison non renseignée reste non planifiée et son blocage est expliqué. F03-E4 : déplacement manuel et mise à jour directe en surcharge refusés avec conservation de toutes les affectations. F03-E5 : baisse de capacité ou dimension ajoutée après planning bloque le départ groupé et individuel sans modifier les expéditions ni le stock. Une clé/unité utilisée reste stable.

F02-H2 : départ et arrivée distincts conservés sur chaque tournée ; le retour distant empêche une affectation qui dépasse la journée et la fin ouverte l’autorise sans faux retour. F02-E3 : changement de profil ne déplace pas une tournée existante ; remplacement client de l’instantané ignoré ; changement de conducteur invalide les trajets vérifiés. Les ETA et pauses utilisent le même calcul au planning.

F06-H2 : CSV avec unités et charges nulles explicites, GPX avec points de départ et fin. Interface 390 px : changement au clavier du départ propre, coordonnées obligatoires uniquement lorsqu’elles sont visibles, contrôle axe du formulaire, absence de débordement de page. La carte et Waze distinguent les deux lieux.

Migration des ressources : tournées historiques et définition de l’autorisation d’historique inchangées ; helpers privés non exécutables par anon ou le conducteur.
