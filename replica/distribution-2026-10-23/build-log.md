# Journal de livraison

23 octobre 2026 : base main et marqueur production identiques (5e91620). APIs et migrations requises présentes, vérifiées en lecture. Reconnaissance des cinq ERP terminée ; lot Q1–Q3 implémenté dans S02/S03. Aucune migration ou mutation métier réelle.

L'environnement d'exécution local s'est arrêté avant toute écriture. Livraison des sources par GitHub ; build et tests confiés aux workflows existants. CI en attente ; aucune fusion ni publication annoncée à ce stade.

Premier passage navigateur b46549c : 286 réussites, deux scénarios en échec (focus et fixture conditionnement), corrigés. Captures ES/FR/EN produites. Sur 65e59e4 : budget initial, concurrence PostgreSQL, Contacts, Achats, Agent Coco et régression de sécurité réussis ; suite finale en cours. Les sorties restent générées et testées par CI.

## Lot restant Q4/Q5/S1/S2/S3

Base de travail : `f41553c`, lot catalogue publié par la PR #239. Les cinq
améliorations restantes sont implémentées sur `feat/distribution-commitments`.
Reconnaissance corrigée : le moteur de substitutions existait ; il a été étendu.
Le portail B2B séparé ne permet pas les mutations de l'ancien client ERP : ce
cloisonnement est conservé, l'accord externe est enregistré par le vendeur.

Validation locale : compilation de 206 actifs, syntaxe, typage, reproductibilité,
budget initial 14 scripts / 780621 octets (plafond 850000), CSS 299932 (plafond
300000). Régressions navigateur : 85 réussites, dont nouveaux scénarios ES 1440,
FR/EN 390, erreurs/reprise et fermeture lors d'un changement de session/route.
Captures relues : tableau desktop et cartes mobiles ; aucun débordement de page.
Le Chromium du runner a été extrait d'un paquet npm temporaire après échec du
téléchargement Playwright ; aucune dépendance applicative n'a été ajoutée.

La suite globale locale a détecté deux erreurs de fixture ensuite corrigées et
un test de contrat entrepôt qui devait suivre la délégation au moteur existant.
Les tests ciblés ont été relancés. La CI vérifiera la révision finale complète,
y compris les sessions concurrentes PostgreSQL 17, avant migration et fusion.

Précontrôle production en lecture : interfaces attendues présentes, aucune option
ancienne encore proposée. La migration ne modifie aucune donnée métier réelle.
Le workflow Pages vérifiera aussi le nouvel actif `coco-sales-commitments.js`,
en plus du commit réellement servi et des actifs catalogue.

Dernière validation ciblée du backend : 23 tests réussis (distribution, historique
commun, zones entrepôt). Le scénario de livraison partielle vérifie aussi que
l’alerte se ferme après la quantité promise, malgré un reliquat non promis.

CI : les trois listes attendues des tests de fenêtre Notifications ont été
complétées avec les nouvelles catégories, en conservant les comparaisons exactes
par rôle. Un scénario vérifie aussi leurs compteurs et filtres serveur.
Audit axe local limité au nouveau dialogue, à 390 et 1440 px : aucune violation
automatique signalée (une vérification incomplète dans chaque taille). La CSP
est restée active ; aucune conclusion de conformité globale n’est tirée.

Revue finale : libellés des activités et accords de substitution ajoutés aux
historiques existants et au catalogue FR/ES/EN. Les 25 scénarios du suivi de
dossier passent, dont trois vérifications des nouveaux libellés. Les 71 scénarios existants
du contrôle ciblé (préparation, suivi, flux et révision de devis) avaient réussi
lors du même contrôle ; aucun envoi client n’a été effectué.

Le job CI autonome `dossier-discussion` reconstruisait uniquement les traductions
et servait les anciens scripts racine. Il reconstruit désormais les sources
canoniques et vérifie leur reproductibilité avant ses tests, comme la publication.
Les nouveaux tests de libellés ont révélé cette divergence ; leurs exigences
FR/ES/EN sont conservées.
