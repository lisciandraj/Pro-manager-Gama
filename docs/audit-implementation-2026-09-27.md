# Mise en œuvre de l’audit stocks, produits, achats et ventes

Cette version implémente les recommandations logicielles de l’audit du 27 septembre 2026. Elle ne comptabilise aucun comptage supposé et ne choisit aucun seuil ou méthode de coût pour l’entreprise.

| Recommandation | Réponse dans le logiciel | Choix ou action métier restant à réaliser |
|---|---|---|
| Stock cohérent entre fiche et emplacements | Protection en base, synchronisation des quantités, imports d’ouverture localisés et justifiés, simulation avec rollback | Compter les références signalées et justifier leurs écarts |
| Ajustements sensibles contrôlés | Seuils en quantité et valeur, motifs imposant validation, approbateur distinct ; exception administrateur explicitement autorisée et justifiée | Choisir les seuils, motifs et habilitations |
| Données articles exploitables | Diagnostic des champs manquants, exclusion motivée du réapprovisionnement, contrôle d’activation optionnel, brouillons importables et modifiables | Compléter fournisseurs, unités, prix et règles ; distinguer les variantes physiques |
| Scan sans validation implicite de toute la ligne | Modes unité, conditionnement et confirmation de quantité ; contrôle physique d’emplacement configurable ; emballage et clôture explicites | Choisir le mode et tester scanners et emplacements réels |
| Lots et dates | Les ouvertures importées passent par les contrôles de lot existants, comme les réceptions, transferts et préparations | Activer le suivi sur les familles concernées, renseigner les dates et exercer un retrait |
| État partagé des processus | Calcul serveur commun aux cartes, détails, alertes et clôtures ; services, avoirs, retours ouverts, réouverture après changement | Affecter responsables, prochaines actions et échéances |
| Réception–facture–paiement | Quantités reçues sans facture rapprochée visibles et alertées ; contrôle de rapprochement avant paiement conservé | Enregistrer les factures et paiements réels |
| Valorisation explicable | FIFO ou coût moyen mobile par produit, ouverture observée, couches et journal, frais de réception et avoirs, rapprochement avec comptes de stock et de sorties | Valider méthode, coûts d’ouverture, ventilation, conversions en USD et comptes |
| Escalades utiles | Achats et ventes : échéances dépassées, blocages sans responsable ; historique des écarts de stock | Traiter les alertes et fixer les délais |
| Montée en charge | Pagination serveur du suivi et des nouveaux diagnostics, tests d’interface actualisés, contrôle des verrous, scénario PostgreSQL à sessions concurrentes en CI | Fixer les objectifs de temps, puis mesurer une charge représentative |

## Accès aux contrôles

- **Produits → Qualité des données et stock** : écarts et fiches à compléter. La justification d’un écart conserve son état observé ; elle exige d’abord la cohérence entre fiche et emplacements.
- **Entrepôts → Valorisation et frais de réception** : activation par produit, historique, affectation de frais et comptes de rapprochement.
- **Entrepôts → Contrôles techniques** : écarts courants, écarts historiques, cohérence des quantités valorisées et verrous en attente.
- **Règles opérationnelles** : seuils, motifs, modes de scan, contrôle d’emplacement, activation des fiches et exceptions d’approbation.
- **Suivi de processus** : mêmes contrôles de responsable, échéance et clôture pour achats et ventes.
- **Import** : choisir un emplacement et une justification pour une ouverture positive. Un brouillon est importé sans stock et reste dans les articles archivés/inactifs jusqu’à sa complétion et activation. L’enrichissement d’un article actif ne l’archive pas.

## Limites explicites de valorisation

La méthode n’est pas appliquée rétroactivement. Avant activation, le stock courant reste une estimation au coût de fiche ; aucune valorisation passée n’est inventée. Après activation, l’ouverture, les réceptions et les sorties alimentent le journal. Les transferts internes conservent la valeur. Les frais arrivés après consommation sont répartis entre valeur restante et coût des quantités sorties. Un avoir de frais utilise un montant négatif et une référence distincte ; les coûts ne peuvent devenir négatifs.

Les mouvements historiques restent conservés. Le retour client reprend le coût de l’expédition retrouvée, sinon sa provenance indique explicitement une estimation. Le rattachement des comptes permet de comparer le sous-registre aux écritures comptabilisées, sans générer automatiquement des écritures. Les comptes partagés avec d’autres opérations peuvent présenter un écart à expliquer. La facture externe est suivie séparément de l’achèvement opérationnel.

## Validation et reprise

Les tests SQL reconstruisent toutes les migrations sur une base isolée et vérifient notamment les imports, les approbations, les scans, les crédits, les services, les clôtures et FIFO/AVCO. Les tests Playwright vérifient les interfaces actuelles, la recherche, la pagination, les quantités explicites et les dialogues mobiles.

`npm run test:concurrency` nécessite une base PostgreSQL locale vide nommée `coco_concurrency`, indiquée par `STOCK_TEST_DATABASE_URL`. Le script refuse une autre base ou une base déjà remplie. Il reconstruit le schéma, fait concourir deux transferts de huit unités sur un stock de dix et exige un seul succès. Il observe la sérialisation de produits distincts, puis mesure vingt mouvements sur deux sessions. Il vérifie enfin les invariants de stock. Le job GitHub Actions utilise PostgreSQL 17 et n’accède pas à la production.

Les verrous globaux protégeant les documents et leur numérotation restent conservés. Leurs mesures sont à distinguer d’un engagement de performance en production ; la réduction de ces verrous exige de préserver les règles de numérotation et d’annulation.

L’export de reprise doit inclure les nouvelles tables et le journal, comme les autres données applicatives. Une restauration complète exige également la restauration de l’authentification, des fichiers Storage et des paramètres d’hébergement, puis une recette des rôles, d’un mouvement, d’un achat et d’une vente. Les tests isolés ne remplacent pas cet exercice avec les services et le matériel réels.

## État de préparation de cette version

- Validation locale : 109 tests de règles métier et 62 tests d’interface pertinents réussis ; compilation, contrôle de syntaxe, types et vérification des migrations réussis.
- Le scénario PostgreSQL concurrent est prêt dans la CI, mais n’a pas encore été exécuté : l’environnement local ne permet pas de lancer le serveur PostgreSQL natif sous un utilisateur non privilégié.
- Les quatre migrations de l’audit et la publication de l’interface restent à appliquer. L’envoi vers le dépôt public a été refusé par le contrôle automatique, qui demande une autorisation explicite de publication.

## Liste visuelle de préparation

Chaque ligne de prélèvement affiche la photo disponible, la description du produit, sa référence, son emplacement et la quantité préparée sur la quantité prévue. La progression et la coche verte reposent sur les quantités enregistrées par le serveur. Un scan partiel ou refusé ne coche pas la ligne. Le contenu de la commande est également visible avant le démarrage, avec les quantités et emplacements encore à confirmer. Les lignes restent distinctes par emplacement. Les photos utilisent le chargement différé et le cache existants ; un pictogramme remplace une photo absente. Affichage contrôlé sur mobile et sur ordinateur.

## Correctif indépendant : numéro de livraison

Appliqué en production le 27 septembre 2026. L’expédition et sa livraison TMS sont enregistrées ensemble dans le dossier avant l’émission des références. La livraison ne crée donc plus un dossier provisoire et un numéro ENT différent de celui de la commande. Les opérations sont dans la même transaction : un envoi refusé ne laisse pas de références orphelines et une nouvelle tentative conserve les mêmes documents.

La migration corrige les références historiques décalées lorsqu’il existe une seule livraison dans le processus et que le numéro attendu est libre. Elle refuse les collisions, archive les anciennes valeurs et conserve les anciennes références dans les champs d’historique. Les UUID, preuves, numéros fiscaux, états, montants et stocks sont préservés. Les sous-documents multiples restent distincts et rattachés au même dossier.

Validation : quatre tests SQL réussis, dont le scénario d’envoi sur le schéma de production et sur le schéma comprenant les migrations d’audit en attente. Vérification en production : cohérence entre les références du registre et celles des livraisons, disparition des décalages ENT simples, fonction d’envoi corrigée. Ce correctif serveur ne publie pas l’interface ni les quatre migrations d’audit.

## Actions du suivi et affichage des colonnes

Chaque étape de vente et d’achat propose un accès à son écran de travail, avec le dossier concerné : origine, devis, commande, réservation, réapprovisionnement, préparation, transport, facture, paiement et contrôles de clôture. Le résumé reprend les raccourcis de l’étape à traiter. Les actions sont filtrées selon l’accès au module et revérifiées au clic. Avant la création d’une commande, le lien ramène au devis ou à la demande existante.

La facture fournisseur se suit dans Comptabilité → Factures de fournisseur. La création de la commande d’achat ne produit pas une facture comptable. Le raccourci du suivi ouvre le formulaire avec la commande et le fournisseur présélectionnés ; le numéro et les montants restent à renseigner et à valider. Un lien vers une facture existante sélectionne celle-ci par son identifiant, même lorsque des fournisseurs utilisent le même numéro externe.

Le choix des colonnes démarre replié à chaque création d’un tableau. Les anciennes préférences d’ouverture sont ignorées ; le choix des colonnes visibles reste enregistré. Le contrôle reste utilisable au clavier et sur mobile.

Validation locale : 37 tests Playwright sur le suivi, la comptabilité et les contrôles de tableaux réussis ; affichage mobile inspecté. Aucun paiement ou enregistrement de facture n’est déclenché par les nouveaux raccourcis seuls.
