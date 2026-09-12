# Nettoyage du code historique — septembre 2026

Suppressions vérifiées par recherche des références dans les fichiers suivis :

- ancien menu HTML et ses cartes en double : remplacés au démarrage par le menu
  de `gama-menu-final2.js` ; le conteneur principal reste en place ;
- styles exclusivement liés à ce menu : appGrid, appTile, appIcon, moreGrid,
  menuIntro et menuFooter ;
- bouton globalBack remplacé par les en-têtes communs GamaUI ;
- deux listes de suppression des modules vides, leur nettoyage par libellé,
  le blocage CSS et l'observateur inline qui masquaient les notifications ;
- registre MODULES vide de l'interface standard, injecteur de cartes, chargeur
  TMS alternatif inaccessible et styles de badges propres à cet injecteur ;
- traduction globale de « Magasinier » et « Commercial » : les libellés de rôles
  sont déjà définis en espagnol dans le contrôle d'accès ; le TMS conserve son
  chargeur et sa carte ;
- entrées de permissions/menu des anciens écrans autonomes Tareas, Agenda,
  Etiquetas, Ubicaciones, Unidades et Ayuda y soporte, sans écran implémenté ;
- dix anciennes images et variantes de logos sans référence dans le code,
  le manifeste, les styles, la documentation ou les workflows.

Les modules métier chargés directement ou dynamiquement restent utilisés.
Le formulaire et l'archive historiques des devis ont encore des liens actifs
(demandes clients et consultation d'archives) : ils restent disponibles.
Les icônes PWA actuelles et le logo courant restent présents.
Aucune table, migration ou donnée métier n'est supprimée.

Validation : suite Playwright complète, comprenant notifications visibles,
permissions, configuration des modules, navigation, devis, ventes, achats,
inventaire, importations, CRM, RH, TMS et PDF.
