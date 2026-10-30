# Parcours TMS routier

| Cas | Vérification | Automatisation |
| --- | --- | --- |
| F01-H1 | Acquérir une matrice privée complète puis planifier | Base isolée, adapter Edge |
| F01-E1 | Aucun prestataire configuré : explication et planning conservé | Navigateur, Edge |
| F01-E2 | Cache valide sans nouvelle requête, expiration, points changés | Base, Edge |
| F01-E3 | Erreur, réponse mal formée, accrochage lointain, trajet inaccessible | Base, Edge |
| F01-E4 | Double clic, requête concurrente, quotas et session changée | Base, navigateur |
| F01-N1 | Anonyme, conducteur et utilisateur sans droit de dispatch | Règles existantes + nouveaux tests base/Edge |
| F02-H1 | 20, 50 et 100 livraisons avec matrice directionnelle | Benchmark isolé |
| F02-E1 | Départ/retour distincts, pauses, fenêtres, compétences, capacités | Tests TMS existants + benchmark |
| F02-E2 | Tournée partie/manuelle/horaire vérifié protégée | Base et régressions TMS |
| F03-H1 | Bouton, provenance et erreur accessibles à 1280/390 px | Playwright + axe + captures |
| F03-E1 | FR/ES/EN, pas de dépassement horizontal, réponse après déconnexion | Playwright |

Le benchmark et les tests n’écrivent pas dans les données métier de production. Publication : migration additive puis Edge Function puis actifs web, avec vérification du SHA servi.
