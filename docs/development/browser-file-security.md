# Exports CSV et justificatifs comptables

Les exports CSV utilisent `ArcUI.csvCell` / `ArcUI.csvRows`, définis dans le cœur de présentation. Les champs texte commençant par un marqueur de formule (`=`, `+`, `-`, `@`), même après des espaces Unicode ou caractères de contrôle, reçoivent une apostrophe avant l’échappement CSV. Les nombres JavaScript restent numériques : un montant typé `-12.5` n’est pas transformé en texte. Un identifiant fourni sous forme de chaîne n’est jamais converti en nombre pour contourner ce contrôle. Guillemets, séparateurs et retours de ligne sont échappés ; les lignes utilisent CRLF et le BOM reste activé par défaut.

Comptabilité et Flotte rejettent les téléchargements tardifs après changement de session. Le même sérialiseur protège l’inventaire historique, les erreurs d’importation, les sondages, les exports bancaires RH, les lignes de commande, le tableau de bord, le TMS et l’audit. Les permissions serveur et les limites d’export existantes restent applicables.

Un justificatif comptable est validé avant envoi et après lecture : uniquement PDF, PNG, JPEG ou WebP, MIME exact, base64 canonique, limite de deux millions d’octets et signature de fichier cohérente. Le visualiseur ne produit aucun HTML à partir du contenu enregistré. Les images sont présentées dans une fenêtre avec une action de téléchargement ; les PDF sont téléchargés pour le lecteur PDF du poste. Les URL Blob sont révoquées à la fermeture, lors d’un changement de session, à la sortie de page et à expiration. Une réponse d’une ancienne session n’ouvre pas de justificatif.

Vérification locale :

```sh
node --test tests/browser-file-hardening.test.cjs tests/audit-csv.test.cjs
npx playwright test tests/browser-file-hardening.spec.js --workers=1
```

Les tests utilisent des données et fichiers factices. Ils couvrent les sérialiseurs réellement appelés par Comptabilité/Flotte, le refus d’export après changement de session, les formats invalides, l’affichage d’image, le téléchargement PDF et la révocation des URL. Ils ne prétendent pas tester tous les logiciels de tableur ou tous les lecteurs PDF tiers.
