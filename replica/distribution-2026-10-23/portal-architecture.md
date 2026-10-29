# Dernier parcours : accord client B2B (24 octobre 2026)

Le lot précédent a livré Q1–Q5 et S1–S3. Son élément explicitement reporté était
l'accord sur les propositions depuis le portail client actif. L'ancien accès
client ERP reste désactivé. Cette extension suit l'acceptation de devis déjà
utilisée par `gama_b2b_action`: consentement du client, application par GAMA.

| Problème | Existant réutilisé | Extension | Validation |
|---|---|---|---|
| Un accord doit être retranscrit depuis un appel ou un email | sales_fulfillment_options, sales_option_terms, moteur de substitution S2 | Liste, détail et réponse dans les deux variantes du portail | Client autorisé seulement ; conditions exactes ; consentement explicite |
| Le vendeur doit reconnaître l'accord à appliquer | Dossier, historique sales_events, alerte sales_option | Accord B2B visible, bouton d'application et alerte adaptée | Application unique ; contrôles commerciaux existants toujours requis |
| Les conditions peuvent changer entre lecture et réponse | Empreinte commerciale et reçus fulfillment_requests | Empreinte des conditions affichées, instantané conservé | Proposition obsolète bloquée ; relance identique idempotente |

Priorité : terminer S2. Effort moyen, aucune dépendance ni redevance nouvelle.
Références fonctionnelles et distinction sources/tests : `recon.md` ; aucun
nouveau comportement d'un concurrent n'est affirmé pour cette adaptation Coco.

## Contrats et accès

`gama_b2b_fulfillment(list|detail|respond, data)` est une façade invoker vers une
fonction privée definer à search_path vide. Elle appelle `gama_b2b_customer`
pour chaque lecture, écriture et répétition. L'association explicite entreprise,
le module actif, le compte confirmé, la suspension et la MFA restent obligatoires.
Aucun rôle ERP n'est octroyé. Les identifiants transmis ne choisissent jamais
l'entreprise. Pagination bornée à 30 éléments et projection commerciale explicite
sans coûts, marges, prix d'achat, autorisations internes ni approvisionnements.

La réponse ajoute des métadonnées nullable sur l'option canonique : décision,
acteur, date, empreinte et instantané affiché. Le déclencheur d'historique existant
capture la mutation et conserve la provenance Agent Coco quand elle est fournie
par un appel autorisé. Les réponses humaines portent l'identité réelle du client.
Les nouveaux événements du dossier sont traduits en ES/FR/EN.

Acceptée par le client : option toujours `proposed`, décision `accepted`, stock,
commande et factures inchangés. Refusée : option `rejected`, commande inchangée.
GAMA applique ensuite avec `gama_fulfillment_action(respond_option)` : nouvelle
validation d'empreinte, approbation commerciale, crédit, quantités et réservation.
La référence d'accord est produite par le serveur à partir de la preuve B2B.
Une modification impose le retrait et une nouvelle proposition ; la preuve
initiale ne peut pas être remplacée. Aucune notification automatique ajoutée.

Le verrou transactionnel partagé (741932,1), les verrous de lignes et les reçus
existants sérialisent les réponses avec les commandes/préparations. La mutation
verrouille aussi l'association B2B et son activation, puis revérifie l'accès.
Le reçu lie utilisateur, action et charge exacte ; il n'est lu qu'après contrôle
de propriété et d'accès. Le serveur bloque la réutilisation contradictoire.

## Migration, publication et retour arrière

Migration additive créée par le CLI :
`20261024130530_b2b_distribution_agreements.sql`. Aucun changement de données
métier existantes. Précontrôle production : zéro option en attente, historique
et déclencheur actifs. Restaurer toutes les migrations dans une base isolée
avant application. Appliquer le SQL validé avant la nouvelle interface.

L'ERP utilise le workflow GitHub Pages existant. Le portail public utilise le
projet Cloudflare Pages existant `gama-coco` en Direct Upload (pas de source Git
connectée) : construire assets et Pages Functions, conserver la configuration et
les secrets du projet, vérifier le SHA et les hashes servis après publication.

Retour arrière : redéployer les interfaces précédentes ; révoquer EXECUTE sur la
nouvelle façade et sa fonction privée si nécessaire. Garder les colonnes et
preuves reçues, ainsi que le garde serveur qui interdit d'appliquer un accord
B2B périmé. Ne pas supprimer les preuves et ne pas rétablir le rôle ERP client.
Un éventuel correctif de schéma est une nouvelle migration, jamais une édition
de migration déjà appliquée.

## Scénarios de validation

- Clients distincts, identifiant deviné, compte ERP client inactif, vendeur,
  magasinier, administrateur et anonyme ; lecture directe privée interdite.
- Acceptation et refus explicites, prix HT/TVA/TTC, unités de base et conditionnement.
- Empreinte périmée, option retirée, réponse répétée, clé réutilisée et révocation.
- Deux sessions PostgreSQL répondent puis appliquent le même accord : un événement,
  une substitution, aucune réservation supplémentaire sur le dernier article.
- Crédit et marge bloquent encore l'application ; prix manuel/motif préservés.
- Historiques humain/Agent Coco, sans instantané commercial dans l'index générique.
- Portails autonome/intégré, FR/ES/EN, 320/390/768/1440 px, erreurs réseau,
  cases de consentement, fermeture de session, texte échappé et accès clavier.
- Régressions devis, commandes, livraisons et factures partielles via tests existants.
