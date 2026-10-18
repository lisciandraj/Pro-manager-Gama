# Vérification de la charte ERP GAMA — 18 octobre 2026

Cette passe reprend les quatre références fournies et le skill UI/UX Pro Max. Elle complète la charte commune existante. Le point de retour est `e64d3b6f0076aac8b96a577aec7c6e24aa20e7bb`.

## Périmètre

Les changements concernent les tokens, surfaces, icônes décoratives des KPI, tableaux, badges, kanban, graphiques et fenêtres ERP. Les seules modifications de JavaScript métier sont dans le balisage de présentation. Les calculs, requêtes, permissions, états, liens, clés de préférence et gestionnaires sont inchangés.

Les CSS de Projets et des KPI personnels se chargent via le registre différé existant. Les fichiers sous `src/storefront/`, les entrées publiques, leurs API, Supabase et la configuration Cloudflare ne sont pas modifiés.

## Contrôles effectués

| Contrôle | Résultat |
| --- | --- |
| Compilation, sources, fournisseurs, TypeScript, documentation et migrations | Réussis |
| Reproductibilité des fichiers générés | Réussie après les derniers changements |
| Démarrage | 14 scripts ; JavaScript 844 037 / 850 000 octets ; CSS 294 291 / 300 000 octets |
| Contrastes documentés | 23 couples conformes aux seuils de leur rôle ; actions blanches ≥4,57:1, graphiques ≥3:1 |
| Tests unitaires et bases isolées | Premier passage : 460 réussis, 1 ignoré et 1 attente obsolète sur le préchargement CSS de Projets. Attente corrigée : les 9 tests du chargeur repassent avec succès. |
| Parcours métier/interface ciblés | 123 réussis ; 1 échec de glisser-déposer CRM reproduit sur la version précédente |
| Responsive Chrome et Safari/WebKit | 22 scénarios réussis : contrôles, navigation, fenêtres, vues et langues FR/ES/EN de 320 à 1440 px |
| Références d’accueil | 4 scénarios réussis en HTTP : logo, favoris/personnalisation, droits client, menu mobile |

La première sélection responsive incluait aussi les tests de référence d’accueil, dont la fixture bloque toutes les URL HTTPS, y compris localhost. Ces huit exécutions ont donc échoué avant le chargement de l’application. Les quatre scénarios concernés ont été rejoués avec leur configuration HTTP habituelle et réussissent. Les 22 scénarios responsive utilisent une origine HTTPS locale compatible WebKit.

Les captures [PC](../design/erp-home-desktop.png), [téléphone](../design/erp-home-mobile.png) et [fenêtre](../design/erp-dialog.png) proviennent de l’application compilée, avec données locales de test. Aucun enregistrement métier de production n’a été créé pour ces vérifications.

## Point préexistant

Le test `dragging cards saves the stage, handles won/lost and supports cancelling a loss` ne déclenche pas le dialogue de motif de perte lors de son troisième dépôt. L’échec se reproduit sur la version précédente et avec deux exécutables Chromium. Les transitions par sélecteur, les validations gagné/perdu et la récupération après échec passent. Aucun gestionnaire de glisser-déposer n’est modifié dans cette passe.

## Publication

L’envoi initial vers `lisciandraj/Pro-manager-Gama` a été bloqué par le contrôle automatique d’approbation, qui demandait une autorisation de publication explicite. Après présentation du résultat et du dépôt cible, le propriétaire a autorisé l’envoi et la publication le 18 octobre 2026.

La branche a été actualisée sur `e6656ff`, qui contient la refonte indépendante du site public, sans conflit ni modification de ses fichiers. La publication ERP doit passer par la PR, les contrôles GitHub Actions et la vérification du commit réellement servi dans `coco-build.json`, conformément au [guide de publication](pages-publication.md).
