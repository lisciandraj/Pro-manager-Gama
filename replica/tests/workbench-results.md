# Validation de la refonte horizontale — 16 octobre 2026

Base et point de restauration : `54e70e986469dd63a3f27967d1e7763db731c718`.

- Build canonique : réussi, 196 assets versionnés.
- Tests métier/techniques existants : 409 réussis, 1 ignoré, aucun échec.
- Contraste : 17 couples vérifiés, aucun échec AA.
- Sources, types, documentation, vérification des migrations : réussis.
- Reproductibilité et contrôles d’architecture du build : réussis.
- Budgets existants : conservés ; compactage des espaces et commentaires ordinaires des fichiers servis, sans modifier les noms publics ni l’ordre des règles CSS.
- Captures locales de Produits, Ventes, CRM, Documents, Knowledge et Dashboard examinées.
- Affichage, navigation, clavier et responsive : 64 tests réussis sur Chromium et WebKit ; les 22 modules activés vérifiés à 390, 768 et 1440 pixels.
- Régression ciblée : 97 tests réussis au premier passage ; le seul échec concernait la hauteur minimale des boutons de vue. Après correction à 44 pixels, les 6 tests de cette suite passent, dont le test initialement en échec (98 cas distincts validés au total).
- Budgets finaux : 14 scripts, 848 196 octets JavaScript sur 850 000, 291 461 octets CSS sur 300 000.

Défauts reproduits puis corrigés : chevauchement du bouton Retour avec les sous-onglets Ventes en espagnol (largeur mesurée) ; focus initial du menu avant sa première image visible sous WebKit (focus après ouverture) ; espace sous le contenu en paysage pour la barre mobile ; hauteur des boutons de changement de vue.

Des anciennes assertions de navigation ont été adaptées au menu désormais ouvrable. Les suites simultanées utilisent des dossiers de résultats distincts pour éviter les conflits de fichiers de trace. Aucun contrôle métier, budget ou contrainte d’accès n’a été supprimé.

Les résultats CI et la preuve du commit servi seront ajoutés dans le rapport de déploiement.
