# Documents collaboratifs dans Coco

Référence fonctionnelle publique : https://macro.com/ et
https://docs.yjs.dev/api/document-updates. Aucun code de Macro utilisé.

S07 : Documents → Nouveau document partagé → canal existant → texte partagé.
F08 : créer avec un lien dans le canal → ouvrir depuis le message → modifier à
deux → retrouver les deux contributions → exporter le texte Markdown.
F09 : consulter les versions → archiver/réactiver → retirer un membre → refuser
les lectures, liens, sources Agent Coco et nouveaux enregistrements.
F10 : réponse réseau perdue après sauvegarde → texte conservé dans l’onglet →
navigation interne → nouvelle tentative de la même requête sans doublon.

## Architecture

Yjs 13.6.33 et ses dépendances sont épinglés. Le lot local de 80 237 octets est
chargé au premier éditeur, avec sa licence ; aucun chargement depuis un CDN.
La saisie travaille sur un Y.Text et les changements des deux auteurs sont
fusionnés par une Edge Function appartenant au projet Coco. Aucune clé métier
supplémentaire ni fournisseur externe n’est requis.

Quatre tables privées protégées : document, versions, reçus de validation et
reçus de commandes. Les deux tables de lecture ont des politiques limitant les
lignes aux membres actuels du canal. Le navigateur n’écrit directement dans
aucune table. La façade publique reste SECURITY INVOKER.

La fonction `coco-workhub-documents` vérifie le jeton utilisateur, lit le document
avec ce jeton, fusionne les états et calcule le texte en serveur. Elle prépare
un reçu technique par une route réservée au service, lié à l’auteur, au document,
à la version et à l’empreinte de la requête. Le commit repasse par le jeton
original et revérifie MFA, module et appartenance au canal. Une clé de service
n’effectue donc aucune mutation du document au nom de l’utilisateur.

Un conflit de version relance lecture/fusion/commit, au plus quatre tentatives.
Le reçu de commande rend une réponse perdue rejouable sans seconde mutation.
Un navigateur ne peut pas soumettre un faux texte en contournant le validateur.
L’historique conserve l’auteur et les références, sans copier le contenu. Le
résolveur d’historique est remplacé en conservant son OID et en déléguant au
corps précédent ; aucune politique RH, TMS, comptable ou de proposition n’est
réécrite.

La recherche, les liens retour et les sources Agent Coco reconnaissent le type
`workspace_doc`, sous les droits courants du canal. Une référence partagée dans
un autre canal n’accorde pas d’accès au document. Les fichiers métiers et les
articles Knowledge existants conservent leur stockage et leurs règles.

## Comportement et limites

Éditeur de texte/Markdown, pas éditeur riche WYSIWYG. Synchronisation par lecture
toutes les deux secondes pendant l’affichage ; pas de diffusion WebSocket ni de
travail hors ligne durable. La sélection du texte suit les positions relatives
Yjs lorsque les modifications distantes arrivent.

Les brouillons non enregistrés restent en mémoire de l’onglet pendant la
navigation interne. Une fermeture avec des modifications locales affiche
l’avertissement du navigateur ; l’export permet de les conserver. La déconnexion,
le changement de compte et le retrait d’accès effacent l’éditeur et les brouillons.
Aucun miroir documentaire n’est ajouté à localStorage.

Limites : 100 000 caractères de saisie, 200 000 octets de texte UTF-8 et 280 000
octets d’état CRDT, 500 documents par canal, cinquante versions de texte
conservées. L’interface conserve le texte et propose son export en cas de limite
ou d’échec. Les anciennes versions sont consultables ; leur contenu peut être
copié dans le texte actuel, sans rembobiner le graphe collaboratif.

Cette tranche ne couvre pas les feuilles collaboratives, le canvas, les appels,
le calendrier ou la synchronisation complète de messagerie.

## Construction et archivage concurrent

Le build normal régénère le lot CRDT depuis son point d’entrée sous src et
les dépendances épinglées ; l’intégrité et les licences restent reproductibles.
Si une autre session archive un document pendant qu’un brouillon est conservé
dans cet onglet, l’écran en lecture seule indique aussi les modifications
locales non enregistrées. La réactivation reste possible pour un propriétaire
autorisé, puis ce texte peut être enregistré sans perte.
