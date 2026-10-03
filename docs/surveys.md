# Sondages / Encuestas

Le module **Sondages**, dans les modules de vente, est disponible aux administrateurs et commerciaux autorisés. Les restrictions de modules, d’actions et MFA s’appliquent côté serveur. L’éditeur se charge uniquement à l’ouverture.

## Créer et diffuser

1. Ouvrir **Sondages → Créer un sondage**.
2. Saisir le titre, l’introduction et la langue du questionnaire (français, espagnol ou anglais).
3. Ajouter des questions et des sections, les réordonner avec les flèches, et indiquer les réponses obligatoires. Types : texte court, texte long, choix unique, choix multiple, nombre, date, date et heure, satisfaction de 1 à 5.
4. Pour un quiz, cocher l’option de score et renseigner les numéros des choix corrects. Chaque question corrigée vaut un point. Un choix multiple exige exactement toutes les bonnes réponses. Le seuil de réussite est configurable.
5. Facultatif : définir une date de clôture et limiter l’accès aux liens personnalisés.
6. **Enregistrer le brouillon** conserve le travail dans Coco. **Aperçu** permet d’essayer le formulaire sans enregistrer de réponse.
7. **Publier** rend le questionnaire accessible. Dans **Partager**, copier le lien public ou rechercher un contact pour créer un lien personnel. Pour plusieurs personnes, **Envoyer aux contacts sélectionnés** ouvre une sélection avec recherche, filtre par type et sélection de la page courante. La sélection reste disponible entre les recherches (50 contacts maximum). **Préparer les e-mails** crée les liens individuels et permet de vérifier l’objet et le message, puis d’ouvrir chaque e-mail dans Gmail, Outlook ou votre application de messagerie. Il faut confirmer l’envoi dans cette messagerie. Coco distingue « Préparé » et « Ouvert dans la messagerie » ; il ne peut pas confirmer l’envoi ou la livraison. Les adresses manquantes, les doublons et les contacts ayant déjà répondu sont signalés. Aucun e-mail n’est envoyé automatiquement.
8. Dans **Résultats**, consulter les distributions, les réponses et les scores ; **Exporter en CSV** exporte toutes les réponses accessibles.
9. **Fermer le sondage** arrête la collecte. Un sondage fermé peut être rouvert avant sa date limite, ou archivé. Pour changer les questions, **Dupliquer** crée un nouveau brouillon sans réponses et avec de nouveaux liens.

## Liens et données

- Formulaire : `https://gama-coco.pages.dev/surveys.html#<jeton>` ; le fragment n’est pas transmis comme URL au serveur ni comme référent.
- Un lien personnalisé rattache la réponse au client, fournisseur ou contact CRM choisi. Il accepte une seule réponse et peut être révoqué. Le détenteur du lien peut répondre : il ne s’agit pas d’une vérification d’identité.
- Le lien général ne demande ni nom ni e-mail ; il n’empêche pas une personne de répondre plusieurs fois. Des limites de débit protègent l’enregistrement. Une empreinte serveur de l’adresse réseau sert à ces limites et n’apparaît pas dans les exports.
- La publication d’un sondage est indépendante de la publication du catalogue. Le catalogue reste en maintenance tant que son bouton de publication est désactivé.
- Les questions publiées restent figées pour préserver la cohérence des réponses ; les doublons ont leur propre historique. Les brouillons ne sont pas exposés publiquement.
- Limites : 60 questions/sections, 30 choix par question, 70 Ko par requête. L’écran présente les 50 premières valeurs libres par question et les 200 dernières réponses détaillées ; les distributions et le CSV portent sur toutes les réponses.
- Cette version s’inspire des questionnaires et résultats d’Odoo. Elle n’implémente pas les matrices, conditions entre questions, sessions animées en direct, certificats PDF ou campagnes d’e-mails.

## Architecture et validation

`src/features/surveys/surveys.js` administre les questionnaires par `gama_surveys`. Le rendu commun `survey-form.js` est utilisé par l’aperçu et `src/storefront/surveys.js`. `functions/api/surveys.js` relaie vers `gama_survey`, contrôle l’origine et la taille des requêtes et fournit la clé serveur déjà configurée dans Cloudflare ; aucun secret n’est envoyé au navigateur.

Les tables `private.surveys`, `private.survey_invitations` et `private.survey_responses` ne sont pas lisibles directement par les rôles web. Les façades publiques sont `SECURITY INVOKER`. L’API publique ne renvoie ni les corrigés, ni les participants, ni les résultats des autres répondants. Les questions et réponses sont validées côté SQL, les soumissions sont idempotentes, et les versions protègent les modifications concurrentes.

Tests : `surveys-db.test.cjs`, `surveys-api.test.mjs`, `surveys.spec.js`. Les tests utilisent une base isolée ou des données simulées. La compilation Cloudflare utilise `npm run build:storefront` puis Pages Functions ; le projet Cloudflare étant en Direct Upload, une fusion Git ne le déploie pas automatiquement.
