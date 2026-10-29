# Validation du coût standard et de la clôture périodique

Référence : Odoo **19.0 Enterprise**. Le périmètre complet reste celui de `features.csv` ; ce lot n'est pas une déclaration d'équivalence globale.

## Résultats obtenus le 27 octobre 2026

- 13 tests du moteur et de ses accès : coût FIFO/AVCO/standard, produits avant/après configuration, génération de brouillons, validation, sources modifiées, verrouillages, double requête, correction et pagination.
- Migration d'une base isolée déjà valorisée : 1 test réussi, empreintes des sept tables historiques identiques ; une sortie ultérieure conserve le comportement de l'ancien moteur.
- Neuf parcours navigateur FR/ES/EN × 390/768/1440 : ouverture observée, comptes, revue, brouillon, écriture de 96 USD, contrepassation, accessibilité axe et absence de débordement. Les données sont fictives et isolées.
- Suite générale avant le correctif de lecture : 650 tests réussis, deux contrôles PostgreSQL réservés au workflow de concurrence ; aucune défaillance. Le correctif de lecture est couvert par le test de liste et les neuf parcours.
- Concurrence PostgreSQL 17 : deux validations du même lot donnent une seule écriture ; deux générations à la même date donnent un seul brouillon. Workflow [40552540469, tâche concurrence](https://github.com/lisciandraj/Pro-manager-Gama/actions/runs/40552540469/job/122359866555) réussi. La tâche navigateur de ce premier passage a révélé l'alias SQL corrigé ; elle n'est pas une preuve de réussite des écrans.
- Compilation, syntaxe, types, documentation, archives SQL, reproductibilité des actifs et budgets de démarrage réussis. Les gates GitHub du commit final restent requis avant publication.

## Base de production

Migration effectivement appliquée : `20261027180512_accounting_stock19_review`, 34 895 octets, SHA-256 `6924ac10cc62282d757f7f000ec2306b6f29db3de8a9d8aaf00ccdb049f3855a`. Le SQL exact et ses métadonnées sont archivés sous `supabase/sql/applied/`.

[Contrôle enregistré](stock19-production-verification.json) : **30 empreintes de tables inchangées**, 58 écritures, 138 lignes, débit = crédit = **8 552,49 USD**, zéro écriture déséquilibrée. Zéro politique et zéro revue créées par la migration. Les quantités, factures, paiements et rapprochements historiques restent identiques.

Les trois tables privées ont RLS ; elles ne sont pas accessibles directement aux rôles API. La façade publique est invocateur, non exécutable anonymement. Les quatre captures d'historique sont activées. Les avis de sécurité conservent deux avertissements préexistants (fonction d'administration et protection des mots de passe compromis) ; aucun nouvel avertissement. Les trois tables privées fermées apparaissent comme informations RLS sans politique, conformément à leur façade contrôlée.

Une sauvegarde logique ciblée a été conservée avant intervention (2 196 666 octets ; SHA-256 `990269454d169c78fa405e2b76196e9f24ff69d7d4c49e273d734f7d20666222`). Elle ne remplace pas une preuve de restauration physique/PITR complète. Aucune reprise des 1 756 produits à stock positif n'a été exécutée.

## Limites de la preuve

La PR 250 a été intégrée à `main` au commit `706da8e906098bb361df4ec7bafaaa24b6302fcf`. Les douze workflows de son dernier commit ont réussi. Le déploiement Pages `40560762364` a réussi ; le contrôle HTTP en lecture seule confirme cette révision et l'identité exacte des douze actifs comptables vérifiés, dont le module stock. Preuve : [stock19-web-verification.json](stock19-web-verification.json).

Le contrôle authentifié de l'interface de production reste à effectuer avec un accès autorisé. Une tentative de connexion a été rejetée par la revue automatique d'autorisation faute de compte désigné ; aucun contournement de session n'est utilisé. Les essais navigateur ci-dessus utilisent une base isolée, pas les données réelles.

La valorisation perpétuelle à la facture, les régularisations complètes de stock, les comptes par catégorie/emplacement et les clôtures programmées restent ouverts dans la matrice. K02 et K03 demeurent partiels malgré ce parcours opérationnel.
