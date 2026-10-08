# Audit de performance ERP — 8 octobre 2026

Périmètre : démarrage, catalogue, archives de devis, photos, recherche, notifications et diagnostic Supabase. Baseline : `1162c3d913daf8353649d6adea47ab1073d23295`. Les contrôles de données réelles sont en lecture seule ; les scénarios métier utilisent des fixtures isolées.

## Constats et corrections

| Écart | Correction | Vérification |
| --- | --- | --- |
| Archive historique chargée à l’accueil et rechargée même masquée | Charger uniquement dans `billing`, regrouper les événements et joindre les références nécessaires | Aucun appel produits/clients/factures de cette archive à l’accueil ; événements masqués ignorés |
| Catalogue complet chargé en parallèle de la première page Produits | Garder la pagination serveur de 20 lignes ; fournisseurs séparés ; miroir complet réservé à l’édition et aux écrans historiques | 1 836 produits de test, création/édition/archivage et fournisseurs |
| Photos sans borne mémoire et requêtes concurrentes non limitées | Cache LRU : 160 entrées et 4 Mio de caractères base64 ; 2 requêtes maximum ; marge de préchargement de 300 px | Limites, coalescence, erreurs réessayables, changement de session et photo éditée pendant une lecture |
| Cloche calculant un tableau de bord détaillé | Action RPC `badge` limitée au compteur ; appels simultanés partagés | Égalité avec `snapshot` pour administrateur, commercial, magasinier, filtres/préférences et mise en attente ; refus client et sans identité |
| Recherche globale incluse dans le démarrage | Charger moteur et adaptateurs au premier usage | Recherche, raccourcis, fermeture, traductions, liens métier, changement de droits et déconnexion |
| Chaque clic enregistré comme une durée fixe de 1 ms | Event Timing réel, diagnostics locaux LCP/CLS/tâches longues | Observateurs simulés et nettoyage de session ; aucun faux échantillon de 1 ms |

## Mesures reproductibles

`tests/performance-audit.spec.js` utilise 1 836 produits synthétiques sans photos, à froid. Les volumes représentent les réponses JSON interceptées du transport simulé, pas des octets HTTP compressés ni une durée réseau réelle.

| Mesure | Avant | Après |
| --- | ---: | ---: |
| Lectures métier involontaires à l’accueil (produits/clients/factures) | 3 requêtes, 1 837 lignes, 197 952 caractères JSON | 0 |
| Ouverture de la première page Produits | 15 requêtes, 1 876 lignes, 631 686 caractères JSON | 2 requêtes, 20 lignes, 6 663 caractères JSON |
| JavaScript statique déclaré, non compressé | 866 907 octets | 834 999 octets |
| Scripts statiques déclarés | 14 | 14 |
| CSS statique déclaré | 230 443 octets | 230 443 octets |

La première page Produits transfère ainsi **98,95 % de JSON en moins dans cette fixture**. Le démarrage reporte environ 32 Ko de JavaScript jusqu’à la première recherche. Le budget de régression JS passe de 900 000 à 850 000 octets. Les scripts dynamiques, images et données ne sont pas inclus dans ce budget.

Le test PostgreSQL isolé, avec 200 produits en alerte, passe d’environ 32 142 à 67 caractères JSON pour la cloche. Les durées d’un passage isolé ne permettent pas de conclure à un gain de latence réel : cache, réseau et charge varient.

## Base de production et limites

Au relevé : 1 836 produits ; environ 28 Mo pour leur table, dont 24 265 801 octets de photos encodées. Aucune recompression ou modification de photo métier n’est effectuée par cet audit.

Le conseiller de performance Supabase remonte 393 informations d’index inutilisés ; aucun avertissement de performance RLS ni de clé étrangère sans index dans ce relevé. Ces index sont conservés : une absence d’utilisation dans la fenêtre de statistiques ne suffit pas à prouver leur inutilité.

Les statistiques cumulées de requêtes comprennent des versions antérieures, notamment avant les corrections RLS du 6 octobre. Elles ne démontrent pas à elles seules une lenteur actuelle. Les mesures opérationnelles comportent aussi de fortes valeurs extrêmes : pas d’attribution automatique au serveur. Les sessions utilisateur réelles, le rendu mobile sur réseau lent et le P95 après déploiement nécessitent de nouvelles observations. Aucun pourcentage de vitesse globale de l’ERP n’est revendiqué.

Le formulaire historique peut encore demander un miroir complet à son ouverture ; la recherche de cette archive conserve ses limites existantes. Les listes Produits et les modules modernes évitent ces lectures au démarrage. Le plafond du cache photo ne limite pas la mémoire des images déjà décodées dans le DOM.

## Contrôles

- `npm run validate` : syntaxe, types, documentation, migrations, tests unitaires/SQL isolés, fichiers générés et budget.
- Playwright : performance, chargement, recherche globale, édition/fournisseurs, archivage, identité produit, photos et notifications.
- Reconstruction des actifs avec hashes de contenu ; migration additive à la fonction privée existante, sans modification des droits ou données métier.

Les tests d’archive et de notifications ont été adaptés aux intitulés et onglets déjà présents dans l’interface actuelle. Les tests photo défilent jusqu’aux lignes demandées pour vérifier le chargement proche de la zone visible.
