# Supervision et réponse aux incidents

Les journaux métier ne remplacent pas la surveillance. Le code fournit un collecteur branché sur les agrégats ERP et les journaux Supabase, un contrôle de couverture, une alerte expurgée et des unités `systemd`. Leur présence dans Git ne prouve ni installation ni réception par un responsable. Aucun webhook n’a été appelé et aucun ordonnanceur n’a été installé pendant cette implémentation.

## Collecte et alertes

`scripts/coco-collect-security.py` collecte uniquement les agrégats suivants, pour une fenêtre UTC bornée :

| Mesure | Source effective |
| --- | --- |
| Changements de droits | `public.erp_audit_events` : rôle/profil/activation/suppression de profil et tables de permissions module/action/comptabilité ; les quatre déclencheurs de capture doivent être actifs. Le rôle de responsable RH relève du profil ; l’ancienne table `hr_permissions` a été retirée et n’est pas une source. |
| Exports sensibles | `private.coco_security_events`, événement inscrit par l’export applicatif autorisé ; un échec annule l’événement avec la transaction. L’acteur UUID et la portée neutre restent dans ce registre privé ; le collecteur reçoit seulement leur nombre. |
| Appels, échecs, expirations, jetons et charge IA | `private.ai_provider_usage` : appels/réservations créés dans la fenêtre et consommation réglée à leur achèvement. Les montants sont des micro-USD de réservation conservatrice, pas un relevé de facturation du fournisseur. |
| Refus Auth | Journaux `auth_logs`, message structuré `request completed`, statut HTTP 400–499. Cela inclut les identifiants invalides, requêtes incorrectes et limitations, sans lecture des e-mails ni adresses IP. |
| Retraits de facteurs MFA | `auth_audit_logs`, actions `factor_unenrolled` et `factor_deleted`. Une suppression de facteur non vérifié est également un événement ; le compteur n’affirme pas une compromission. |
| Refus d’admission IA | `function_logs`, événement JSON `ai_provider_admission_denied`. Un échec de finalisation possède un événement différent et n’est pas compté comme admission refusée. |

Le point `public.coco_security_aggregate(p_start,p_end)` est réservé à `service_role`, via une fonction privée propriétaire. Aucun rôle applicatif ne peut lire le registre ou appeler l’agrégat. Les fenêtres dépassant 24 heures, futures ou trop anciennes sont refusées. Un propriétaire soumis à RLS ou un déclencheur de capture absent provoque une erreur explicite ; le collecteur ne peut donc pas présenter comme sains des compteurs ramenés à zéro par RLS. La migration ne modifie aucun compte ni donnée métier existante et compose avec la protection MFA de l’export dans les deux ordres d’installation.

Les journaux utilisent le point Management API actuel `GET /v1/projects/{ref}/analytics/endpoints/logs`, SQL ClickHouse sur `logs`, avec bornes explicites et prédicats semi-ouverts `timestamp >= début AND timestamp < fin`. L’ancien `logs.all` est supprimé. Une sonde agrégée des dernières 24 heures vérifie la présence des trois sources et leurs champs documentés. Une source absente, même parce qu’elle est restée silencieuse pendant 24 heures, reste **inconnue/incomplète** ; elle ne devient pas un zéro sain. Les erreurs HTTP, changements de schéma, champs non mappés et réponses tronquées échouent aussi. Aucun message de journal ni enregistrement métier n’est renvoyé au serveur de supervision.

Les correspondances suivent la [documentation des journaux Supabase](https://supabase.com/docs/guides/observability/advanced-log-filtering), les [actions Auth](https://supabase.com/docs/guides/auth/audit-logs), les [champs utilisés par Supabase](https://raw.githubusercontent.com/supabase/supabase/master/packages/shared-data/log-constants.ts) et son [journal HTTP Auth](https://raw.githubusercontent.com/supabase/auth/master/internal/observability/request-logger.go). Deux requêtes de **comptage seulement** ont été vérifiées sur le fournisseur le 7 novembre 2026 : disponibilité/mappage des trois sources et agrégation des trois types d’événements. Aucun journal brut ni donnée personnelle n’a été chargé.

### Configurer le serveur privé

Appliquer la migration revue `20261107212039_security_monitor_aggregates.sql` et déployer les fonctions IA qui émettent l’événement d’admission. Copier `security-monitor.example.json` vers `/etc/coco/security-monitor.json`, propriété `coco-backup`, mode 0600 ; vérifier les seuils du contexte réel. Copier `monitor.env.example` vers `/etc/coco/monitor.env`, root 0600, lu par systemd. Fournir séparément le jeton Management avec la portée `analytics:read` et la clé de service existante du serveur via les variables prévues ou des fichiers réguliers privés 0600/0400 appartenant à `coco-backup`. Aucune permission `database:write` Management n’est nécessaire. Les jetons, URL d’alerte et clés ne vont ni dans Git, ni dans les arguments, ni dans les journaux.

Les sources sauvegardes/certificats sont facultatives et explicitement `not_configured` dans le modèle : leurs compteurs sont absents, sans zéro inventé. Pour les activer, ajouter `backup` avec `root`, `max_age_hours` et, pour exiger le reçu Drive, le `drive_folder_id` vérifié ; ajouter le seuil `backup_failed`. Pour les certificats, renseigner `certificates` avec les chemins absolus **de certificats publics PEM seulement** et `warning_days`, puis le seuil `certificate_expiring`. Le lecteur refuse les liens, types inattendus et fichiers de plus de 256 Kio ; il passe le certificat public à `openssl x509` via stdin, sans ouvrir de clé privée/P12. Un chemin configuré mais indisponible rend la collecte incomplète. Les états sauvegarde absente/ancienne et certificat bientôt expiré sont des jauges ; ils peuvent déclencher à nouveau tant que la condition persiste. GitHub, Cloudflare, les échecs de rétention et les autres sources non raccordées ne reçoivent aucun compteur fictif.

Créer `/var/lib/coco-monitor` en mode 0700, propriété `coco-backup` ; l’unité fournie utilise aussi `StateDirectory`. Le mode sans `--run` valide la configuration sans lire les clés et sans requête :

```sh
python3 scripts/coco-collect-security.py --config /etc/coco/security-monitor.json --output /var/lib/coco-monitor/signals.json --state /var/lib/coco-monitor/collector-state.json
python3 scripts/coco-collect-security.py --config /etc/coco/security-monitor.json --output /var/lib/coco-monitor/signals.json --state /var/lib/coco-monitor/collector-state.json --run
python3 scripts/coco-operations.py signals --file /var/lib/coco-monitor/signals.json --require-collection
```

La sortie version 2 contient `observed_at`, les bornes, `coverage`, `complete`, les compteurs mesurés, les métriques IA et `alert_counts` dépassant les seuils. Une source requise manquante produit `complete=false`, `monitor_failed=1` et une sortie non nulle ; aucun curseur n’avance. Le fichier et le curseur sont privés et remplacés atomiquement. Les exécutions réussies enchaînent des fenêtres sans chevauchement ; une marge d’ingestion configurable retarde leur fin. Le curseur est lié au projet. Après une panne dépassant les 24 heures interrogeables, la collecte refuse de sauter la période : consigner l’écart et récupérer les preuves disponibles avant de redéfinir le point de départ. La première exécution commence à la fenêtre configurée ; elle ne certifie pas l’historique antérieur.

`signals --require-collection` refuse les anciens fichiers manuels version 1, les relevés incomplets, les compteurs obligatoires absents et les données âgées de plus de deux heures. `--send-alert` utilise uniquement `COCO_ALERT_WEBHOOK_URL`, HTTPS sans identifiants dans l’autorité, sans redirection, échéance cinq secondes. La charge contient seulement `service`, `event`, `count`, `time`. Une destination absente ne prouve pas la réception d’une alerte.

`coco-security-monitor.service` exige la réussite de `coco-security-collect.service` avant d’évaluer les seuils. La panne du collecteur déclenche `coco-security-collect-alert.service` avec l’événement expurgé `monitor_failed`. Installer les unités revues et leur minuteur seulement après un premier relevé complet, un test d’alerte factice et son acquittement. Aucun accès du serveur, seuil en production, ordonnanceur ou destinataire n’a été configuré ici. Surveiller aussi la panne du serveur/minuteur par un canal externe ; un processus arrêté ne peut pas s’alerter lui-même.

## Exercice sans mutation

```sh
python3 scripts/coco-operations.py incident --scenario account-compromise --output /chemin/prive/exercice-compte.json
python3 scripts/coco-operations.py incident --scenario backup-failure --output /chemin/prive/exercice-sauvegarde.json
python3 scripts/coco-operations.py incident --scenario data-exposure --output /chemin/prive/exercice-donnees.json
```

Chaque commande crée un compte rendu nouveau et privé, marqué `dry-run`, sans accès réseau, notification ou révocation. Un modèle rempli n’est pas la preuve d’un exercice réussi : le responsable ajoute séparément participants, chronologie, observations et actions testées sur la recette.

## Procédure d’incident

1. Le responsable nommé ouvre un dossier privé : heure de détection, systèmes concernés, faits vérifiés et décision de qualification. Préserver journaux et preuves nécessaires sous contrôle d’accès ; ne pas publier le contenu métier dans Git ou un ticket public.
2. Pour un compte compromis, désactiver son accès métier, révoquer ses sessions et les délégations concernées, contrôler les facteurs MFA et les autres comptes privilégiés. Effectuer les essais de refus avec des comptes de recette. Ne pas retirer tous les moyens d’accès de secours.
3. Pour un secret compromis, limiter d’abord le périmètre affecté ; utiliser la procédure coordonnée de rotation et de rechiffrement. Une clé Supabase globale ne doit pas être remplacée sans inventaire de ses consommateurs. Ne jamais remettre un secret dans le rapport.
4. En cas d’anomalie Agent Coco, désactiver les écritures et conserver lecture, reçus et approbations. Ne pas restaurer l’ancien protocole d’auto-confirmation. Suspendre les tâches sortantes concernées plutôt que d’effacer leurs traces.
5. Pour une restauration, utiliser un hôte et un réseau isolés, la procédure [recovery.md](recovery.md) et des comptes fictifs de recette. Vérifier la portée des données, fichiers privés et refus entre clients avant toute décision de reprise.
6. Le référent données/juridique qualifie les obligations applicables et les notifications aux personnes/autorités. Ce code n’envoie aucune notification légale et ne décide pas du délai juridique.
7. Documenter la cause, les mesures, la durée de rétablissement, les preuves de validation et les actions restantes. Tester une amélioration mesurable après l’incident.

## Conservation

La rétention des sauvegardes chiffrées est distincte des durées légales des factures, pièces fiscales, preuves/signatures/GPS, documents RH, OCR, historiques IA et demandes de droits. Les responsables métier/données approuvent une durée et un motif pour chaque catégorie, les exceptions de gel légal et le contrôle d’accès. Ne pas activer une purge générale sur une durée inventée.

Le modèle `operations/systemd/backup-retention.example.json` refuse la suppression avant approbation. La commande `retention` est à blanc par défaut, conserve au moins deux copies complètes et ne supprime jamais une copie partielle/inconnue. La protection immuable doit être appliquée à la destination hors fournisseur avec une identité de conservation distincte ; le compte de sauvegarde ne doit pas pouvoir désactiver cette protection. Le script ne prétend pas créer un verrou objet immuable sur un stockage dont il ne connaît pas l’API.
