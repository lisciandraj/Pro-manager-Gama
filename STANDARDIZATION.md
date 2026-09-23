# Socle Coco ERP

L'interface partage désormais ses primitives visuelles, son registre de modules, sa navigation et ses contrats de données. Les écrans métier existants utilisent ce socle tout en conservant leurs règles, références et permissions.

| Zone | Source de référence | Utilisation |
|---|---|---|
| Navigation et droits de visibilité | `src/app/registry.js` | Menu, catalogue des modules, titres et rôles |
| Navigation et cycle de rendu | `src/app/router.js` | `ArcRouter.open/show/onEnter`, événements de changement et sortie |
| Composants | `src/ui/components.js` | Bouton, champ, formulaire, panneau, dialogue, tableau, pagination, badge, onglets et KPI |
| Couleurs et relief | `architect-ui.css` | Tokens Coco ERP et états visuels communs |
| Styles compilés | `src/ui/base.css`, `module-styles.css`, `components.css` | Remplacent les blocs CSS intégrés dans HTML et les injecteurs JS |
| Objets et formats | `src/domain/` | UUID distinct des identifiants métier, adaptations SQL, erreurs, montants et dates |
| Lecture et commandes | `src/data/service.js` | Pagination serveur, collecte paginée, cache invalidable et RPC |
| Répertoires | `src/modules/directories.js` | Fournisseurs, clients et produits |
| Types SQL | `src/data/database.types.ts` | Contrats générés depuis Supabase |
| Base de données | `supabase/` | Historique vérifiable, reconstruction et opérations transactionnelles |

## Commandes de travail

```sh
npm ci
npm run build
npm run dev
npm run check
npm run typecheck
npm run verify:migrations
npm run test:unit
npm test -- --workers=3
```

Exécuter `python3 scripts/build-i18n.py` après un changement de libellés, puis `npm run build`. La compilation produit le cœur JavaScript et les feuilles de style, met à jour les empreintes des ressources et génère `dist/`. Les fichiers compilés à la racine sont conservés pour l'hébergement GitHub Pages existant. Ne pas les modifier manuellement. Le workflow vérifie leur reproductibilité.

## Convention pour un nouvel écran

1. Déclarer ses métadonnées dans le registre unique.
2. Déclarer explicitement champs et colonnes ; les colonnes SQL sensibles ne sont jamais affichées automatiquement.
3. Utiliser `ArcUI` pour les composants et `ArcUI.render/mount` après le rendu, afin d'associer labels, droits, traductions et sélecteurs.
   Ouvrir l'écran avec `ArcUI.header()` : l'icône du module s'y peint seule tant que la `<section>` porte l'identifiant du module, sinon lui passer `module`.
4. Lire via `ArcData` et envoyer les écritures métier aux commandes serveur existantes. Les validations du navigateur accompagnent celles du serveur.
5. Retourner la fonction de nettoyage depuis un hook `ArcRouter.onEnter` quand l'écran installe des ressources temporaires.
6. Réserver les styles de domaine à son contenu propre : calendrier, Kanban, timeline, etc. Les boutons, champs et panneaux suivent les tokens communs.

## Changements par domaine

- **Fournisseurs** : formulaire partagé, erreurs et prévention des soumissions simultanées ; tableau avec recherche, tri et pagination serveur ; édition, archivage et restauration préservent les champs non affichés.
- **Clients et produits** : mêmes tableaux déclaratifs et pagination serveur, contrats canoniques et adaptateurs limités aux anciens éditeurs. Les tarifs, photos, imports et identifiants métier gardent leurs comportements.
- **Vente et logistique** : montage partagé, composants et formats harmonisés ; le formulaire historique de devis utilise une seule commande transactionnelle, sûre à relancer. Les circuits commandes, réservations, préparation, livraison et paiement gardent leurs RPC métier.
- **RH, CRM, projets, comptabilité, flotte et retours** : navigation et rendu communs, styles extraits, contrôles partagés. Comptabilité, flotte et retours se chargent à la première ouverture. Le dialogue Projets conserve ses protections spécifiques contre la perte des modifications et les conflits de version.
- **Menu et surfaces** : relief et contraste conservés ; bloc d'activité récente et promotion du tableau de bord retirés du bas du menu. L'ordre personnalisable des modules reste disponible ; les quatre KPI personnels sont passés en tête du tableau de bord.

## Compatibilité et limites explicites

Cette migration introduit un socle compilé et remplace les mécanismes transversaux ; elle ne convertit pas tous les anciens fichiers métier en TypeScript. Les interfaces `Gama*`, les éditeurs documentaires spécialisés et certaines mises à jour Realtime restent des adaptateurs de compatibilité. Les modules ne sont pas tous chargés à la demande, car certains fournissent aussi des fonctions aux autres écrans.

Les tableaux des trois répertoires sont déclaratifs. Les autres tableaux passent par le rendu et le style communs, avec l'adaptateur mobile existant pour leurs colonnes métier. Les calculs de prévisualisation du navigateur ne remplacent jamais les totaux validés côté serveur.

Le typecheck valide les contrats TypeScript ; il ne promet pas la vérification statique de tout le JavaScript historique. La couverture fonctionnelle est assurée par les parcours Playwright et les tests de base de données. Aucun gain de performance n'est annoncé sans mesure avant/après.
