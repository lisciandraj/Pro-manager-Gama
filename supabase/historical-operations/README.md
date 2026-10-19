# Opérations ponctuelles retirées de la livraison

Ces deux fichiers sont conservés avec leurs octets originaux. Ils ne figurent pas dans le registre de production observé le 19 octobre 2026 et suppriment le catalogue et des données liées. Ils ne doivent pas être rejoués pour une mise à jour ou une restauration.

`migration-history.json` conserve leurs empreintes sous leur emplacement d’archive. `observed-migrations/` conserve séparément deux définitions récupérées dans le registre distant, sans les ajouter au chemin d’exécution.

Le registre distant reste la référence de ce qui a été exécuté. La ressemblance des noms ne suffit pas à certifier l’équivalence des 70 paires historiques. `migration-preflight.cjs` vérifie une photographie du registre et une liste explicite de nouveaux fichiers ; il n’exécute ni `db push`, ni `migration repair`.
