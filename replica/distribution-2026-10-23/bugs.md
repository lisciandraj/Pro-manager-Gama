# Défauts et limites

Aucun défaut du lot confirmé avant exécution CI. Les scénarios de réseau, unité modifiée et article désactivé disposent de tests négatifs.

Limite de l'environnement : le téléchargement Chromium local a renvoyé une archive invalide, puis l'environnement s'est arrêté. Les compilations/tests et captures seront réalisés en CI. Cette limite ne justifie aucune suppression de contrôle.

## B01 — S3 — Dépassement du budget CSS initial

Reproduction : build puis check:startup sur b46549c. Attendu : CSS initial ≤ 300000 octets. Observé : 301528. Preuve : job architecture 120542245086. Correctif : charger sales-catalog.css à l'ouverture via le chargeur existant ; budget conservé. Validation CI requise.

## B02 — S3 — Focus après Échap

Reproduit deux fois dans le job ventes 120542244911 : la fenêtre se ferme mais le bouton d'ouverture n'est pas focalisé. Le désactiver pendant le chargement faisait perdre le point de retour d'ArcUI. Correctif : réactiver et focaliser le bouton juste avant l'ouverture du dialogue. Test de clavier conservé.

## B03 — Conditionnement modifié / fixture

Le scénario de changement de facteur échouait : la fixture partageait ses objets d'unité avec la réponse déjà reçue, contrairement à JSON sur le réseau. La fixture renvoie désormais une copie. Le catalogue conserve aussi le facteur choisi séparément et le recontrôle à l'ajout, même si un objet produit ou une recherche est rafraîchi. Aucun changement silencieux de quantité accepté.

## Lot restant : défauts corrigés et limites connues

- L'activité d'un devis sans commande échouait sur un alias SQL `q` ambigu : alias corrigé et test de création/clôture ajouté.
- Le formulaire de substitution demandait un prix sans source ni motif : tarif commun réutilisé, motif requis pour le manuel.
- Les marges/crédit n'étaient pas revérifiés lors de la substitution : contrôle transactionnel ajouté, avec annulation complète en cas de refus.
- Une ancienne proposition sans empreinte doit être retirée et reproposée. Aucune option proposée de ce type n'existait lors du précontrôle production.
- Les dates restent des projections sur achats datés et jours calendaires saisis. Aucun SLA transport, calendrier férié ou réservation d'arrivage futur n'est créé.
- Lors du lot précédent, les substitutions se validaient par accord externe référencé ; le consentement B2B reporté est traité dans la suite ci-dessous.

## Accord B2B — suite du 24 octobre

- Ajout du parcours sur le portail actif, sans ouverture des anciennes RLS clients.
- La réponse garde les conditions exactes affichées ; un changement interdit
  l'application, même avec une nouvelle référence d'accord externe.
- Réessai du client et application par GAMA utilisent les reçus canoniques.
- Les montants d'une proposition de date/livraison partielle restent ceux de la
  ligne initiale ; seuls les remplacements modifient le prix présenté.
- Aucune notification client automatique. L'accord accepté attend toujours
  l'application par GAMA. Les dates continuent d'utiliser les jours calendaires.

- La validation complète a signalé une assertion de nom de fonction devenue
  obsolète après l'ajout du garde B2B. Le test vérifie désormais les deux
  délégations jusqu'au moteur canonique et conserve ses assertions de zones.
- La référence serveur B2B utilise UTC : un changement de fuseau entre deux
  appels ne modifie pas le reçu idempotent (test de relance dédié).
