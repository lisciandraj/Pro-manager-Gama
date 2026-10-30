# Optimisation routière du TMS

État : 30 octobre 2026. Périmètre GAMA : 20–100 livraisons et 2–5 véhicules par jour.

## Décision et solutions comparées

| Solution | Adéquation | Coût et exploitation | Décision |
| --- | --- | --- | --- |
| Matrice OSRM privée + planificateur Coco et recherche locale | Temps et distances directionnels ; capacités, horaires, pauses, créneaux, priorités et qualifications Coco | Pas de licence de solveur ; instance routière, mises à jour OSM, sauvegardes, supervision et éventuelle authentification à financer | Implémentée : utilise PostgreSQL et une Edge Function existants dans l’architecture |
| OSRM + VROOM auto-hébergés | Réaffectation et recherche multivéhicule plus poussées ; capacités multidimensionnelles, fenêtres multiples, compétences, pauses et points de départ/fin | Logiciels libres ; service et exploitation supplémentaires ; adaptateur et validation serveur des résultats à construire | Suite logique si les gains du moteur natif restent insuffisants ; non déployée |
| OR-Tools + matrice privée | Grande souplesse pour des contraintes particulières ; recherche bornée et prise en charge des VRP | Pas de licence commerciale ; environnement Python/C++ et service séparé | Plus de maintenance pour le volume actuel ; non intégrée |
| GraphHopper géré | Matrice et optimisation, hébergement prestataire | Tarifs publics consultés : Basic 69 €/mois, 30 lieux et 2 véhicules ; Standard 199 €, 80 lieux et 10 véhicules ; Premium 479 €, 200 lieux et 20 véhicules. Pour un seul calcul de 100 livraisons, examiner Premium ou un contrat spécifique. TVA, crédits, fréquence des recalculs et SLA à confirmer | Alternative sans serveur routier à exploiter ; adaptateur non inclus |
| Google Route Optimization | Optimisation multivéhicule, écosystème Google et options de trafic selon API/configuration | Facturation Fleet Routing par livraison et par requête dès deux véhicules ; facturation Cloud, quotas, conditions de conservation des données et couverture trafic à vérifier | Pas de dépendance Google activée ; prix non extrapolé sans SKU et fréquence choisis |
| OSRM public FOSSGIS de la carte | Tracé facultatif dans l’ordre déjà planifié | Service communautaire, sans engagement contractuel GAMA | Conservé uniquement pour l’option cartographique existante ; jamais utilisé pour obtenir la matrice critique |

Sources officielles consultées : [OSRM Table](https://github.com/Project-OSRM/osrm-backend/blob/master/docs/http.md#table-service), [VROOM API](https://github.com/VROOM-Project/vroom/blob/master/docs/API.md), [OR-Tools VRP](https://developers.google.com/optimization/routing/vrp), [GraphHopper](https://www.graphhopper.com/pricing/), [Google facturation](https://developers.google.com/maps/documentation/route-optimization/usage-and-billing). Tarifs consultés à la date ci-dessus, à reconfirmer avant achat. Le dimensionnement et le choix sont une appréciation technique pour GAMA, pas un devis d’hébergement.

## Contraintes et limites du moteur

Le planificateur serveur canonique garde ses verrous par configuration et journée, ses permissions TMS/MFA et son ordre de verrouillage expédition → livraison → tournée. La sélection de ressources respecte absences RH, disponibilité Flotte, véhicule unique, poids, volume, quatre dimensions supplémentaires et charges inconnues. Les règles par livraison conservent jours/dates, conducteur imposé, compétences et équipements. Les horaires de chaque conducteur, son facteur de vitesse, les trois fenêtres de début de service, les pauses et ses départs/retours indépendants restent évalués.

Les tournées commencées, en chargement, terminées, historiques, mixtes, ajustées manuellement ou possédant un horaire vérifié restent protégées. Les marchandises, préparations et départs ne sont pas modifiés par la mise en place technique. Le calcul quotidien reste une action métier existante avec son historique actuel.

Avec une matrice valide, la sélection des arrêts utilise les **minutes routières** ; elle ne se contente plus de tracer l’ancien ordre. À priorité identique, une livraison réservée au conducteur courant est traitée avant les tâches génériques. Ceci évite que l’équilibrage remplisse ce conducteur et abandonne ensuite sa livraison imposée.

Une recherche locale 2-opt améliore ensuite chaque tournée, avec recalcul complet de toutes les arêtes directionnelles et de tous les horaires. Une inversion n’utilise jamais la formule simplifiée d’une matrice symétrique. Les ressources, charges et affectations sont identiques pendant cette recherche. Elle conserve l’ordre des catégories de priorité et n’accepte qu’une solution faisable de score inférieur : secondes de durée totale + 3 secondes par kilomètre. La durée inclut service, attente, pause et retour. Le premier parcours valide reste le repli.

La recherche est bornée à 4 passes, 800 essais et 750 ms par véhicule, avec au plus 50 livraisons par recherche. Une tournée plus grande conserve la sélection routière native. C’est une heuristique améliorée, sans optimum global garanti, sans échange d’arrêts entre tournées après la phase d’affectation et sans trafic en temps réel ni restrictions poids lourds. La durée d’un véhicule est comparée à sa fin de service ; les totaux du benchmark additionnent tous les véhicules.

Une matrice valide ne transforme pas un horaire en vérification humaine : les ETA restent `estimated`, et les contrôles de chargement, de départ et les horaires vérifiés existants sont conservés.

## Données privées, cache et erreurs

- Le navigateur envoie seulement la journée à `tms-routing`. Les points sont lus par un RPC avec la session du demandeur, MFA et droits de dispatch. Aucun appel privilégié n’a lieu avant ce contrôle.
- L’Edge Function transmet uniquement `[longitude, latitude]`, y compris les départs et retours. Elle n’envoie aucun nom, identifiant de livraison, adresse, téléphone ni position GPS du chauffeur. Les coordonnées restent personnelles : choisir un hébergement et un contrat adaptés.
- Le serveur OSRM est configuré dans les secrets de l’Edge Function. Pas d’URL ni de clé prestataire dans le navigateur. HTTPS obligatoire, pas de redirection, pas d’hôte public de démonstration, pas de paramètres secrets dans l’URL ; jeton HTTP optionnel.
- Au plus 128 lieux distincts, départs/retours compris. Lots de 40 sources × 40 destinations, deux requêtes simultanées au plus, réponse limitée à 2 Mio, délai fournisseur global de 45 secondes. Le serveur doit renvoyer distances ET durées, sans cellules calculées par `fallback_speed`, avec un accrochage à une route à 500 m au plus.
- Une matrice entière est enregistrée en transaction ; tout échec de lot conserve le mode estimé. Des paires nulles restent inaccessibles : elles ne sont jamais remplacées par une liaison aérienne.
- Cache privé par journée, empreinte des points arrondis à six décimales, identité de service/profil/version de réseau, expiration de 24 heures. Une nouvelle coordonnée ou l’expiration invalide l’usage routier. Le retrait de points au départ d’un camion conserve la matrice pour les arrêts restants. Pas de rafraîchissement externe à chaque actualisation de carte de 15 secondes.
- Verrou et bail serveur de 2 minutes contre les doublons, délai d’une minute entre acquisitions, maximum global de 20 acquisitions par jour. Un cache valide est réutilisable sans nouvelle consommation. Une panne demande une action explicite de reprise ; pas de boucle de facturation.
- Les trois tables sont privées avec RLS et sans accès direct des rôles API. Seul le RPC de validation réservé au service peut accepter une matrice liée au bail et à son acteur. Les messages d’erreur ne copient jamais le corps ou l’URL du prestataire. Purge quotidienne après 48 heures, expiration appliquée même si la purge tarde.
- À l’échec du bouton, le planning existant est conservé. L’actualisation native peut ensuite produire une estimation explicitement étiquetée. Les réponses d’une ancienne session sont ignorées.

Les deux façades de planification et le commit technique de matrice ont un délai API limité à 30 secondes, conformément au réglage [par fonction Supabase](https://supabase.com/docs/guides/database/postgres/timeouts). Les délais globaux et des rôles ne sont pas augmentés. Un dépassement annule la transaction ; il n’applique pas un demi-planning.

## Activation externe nécessaire

La migration et l’Edge Function peuvent être publiées sans service routier. Dans ce cas, **Optimiser avec les temps routiers** indique que le service reste à configurer, et le planificateur natif amélioré utilise son estimation habituelle. Ne pas présenter ce mode comme une optimisation sur des routes réelles.

Pour activer la matrice :

1. Exploiter une instance OSRM privée avec l’extrait OSM Équateur, profil voiture et service Table incluant distances et durées. Le choix CH/MLD et la configuration doivent être validés sur cette capacité. Un endpoint qui omet les distances est refusé. Garantir HTTPS, disponibilité, mises à jour, surveillance et accès restreint. Ne pas exposer le port OSRM brut à Internet.
2. Configurer sur l’Edge Function `TMS_OSRM_URL` avec la base HTTPS du service, éventuellement `TMS_OSRM_TOKEN` pour l’authentification du proxy, et `TMS_ROAD_DATA_VERSION` avec la version du graphe. Le proxy doit désactiver ou expurger les journaux d’URL, car le protocole OSRM Table met les coordonnées dans le chemin HTTP.
3. Valider les sens uniques, accès et trajets des vallées avec des adresses connues de Quito. L’extrait municipal d’affichage de Coco n’est pas un graphe routier routable.
4. Dans TMS → Planifier, utiliser le bouton. La mention **Matrice routière privée** et sa date confirment l’utilisation effective ; **Estimation de déplacement** signale l’absence ou l’invalidation de matrice.
5. Vérifier avant départ les créneaux stricts, les conditions locales et les restrictions du véhicule. Aucun trafic en direct, profil poids lourd ou serveur VROOM n’est annoncé par cette livraison.

Aucun abonnement ni hébergement payant n’est créé automatiquement. La mise à jour des secrets ne requiert pas de publier les coordonnées dans un fichier de configuration public.

## Validation reproductible

- `node --test tests/tms-routing-db.test.cjs tests/tms-routing.test.mjs` : cycle de matrice privé, autorisation, expiration, points changés, lots directionnels, valeurs invalides, panne, cache, route inaccessible, idempotence et tournées protégées.
- `node scripts/benchmark-tms-routing.cjs /tmp/tms-routing-benchmark.json` : bases isolées reconstruites avant/après migration, 20/50/100 livraisons et 2/3/5 véhicules. Voir [résultats capturés](../../replica/tms-routing/benchmark.json).
- `npx playwright test tests/tms-routing.spec.js tests/tms-module.spec.js tests/tms-dispatch.spec.js tests/tms-loading.spec.js tests/tms-pro.spec.js --workers=2` : parcours existants, bouton, absence de service, interruption de session, ordinateur/téléphone et axe. Aucun compte ou document de production ne sert de fixture.

Le benchmark utilise un **réseau synthétique directionnel** de forme urbaine allongée, avec sens uniques, franchissements limités, vitesses variables, services de 4 minutes, compétences, équipement, conducteurs imposés et retours distincts. Il ne mesure pas de trafic ou de kilomètres réels à Quito. Les coordonnées synthétiques ne sont jamais envoyées à OSRM public. Les kilomètres et minutes avant/après sont évalués sur la même matrice de test ; l’ancien moteur planifie sur sa propre estimation. Le temps du tableau exclut l’acquisition réseau et la construction des fixtures. PGlite/WASM ne prédit pas la latence PostgreSQL de production, et la borne temporelle peut faire varier le dernier gain trouvé selon la charge de la machine.

Pour 100 livraisons, l’ancien moteur en affecte 96 et le nouveau 100 : les totaux ne portent donc pas exactement sur le même nombre d’arrêts servis. La couverture figure dans les résultats ; ne pas présenter le pourcentage comme une économie commerciale garantie.

### Mesures capturées

| Livraisons / véhicules | Servies avant → après | Km avant → après | Minutes cumulées avant → après | Créneaux respectés après | Calcul avant → après |
| --- | --- | --- | --- | --- | --- |
| 20 / 2 | 20 → 20 | 120.92 → 115.13 | 297 → 286 | 100 % | 0.71 s → 0.88 s |
| 50 / 3 | 50 → 50 | 171.37 → 162.03 | 516 → 500 | 100 % | 2.17 s → 3.62 s |
| 100 / 5 | 96 → 100 | 286.95 → 263.84 | 963 → 921 | 100 % | 7.01 s → 13.63 s |
