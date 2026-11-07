# Supervision et réponse aux incidents

Les journaux métier ne remplacent pas la surveillance. Le code fournit un consommateur de compteurs, une alerte expurgée et des unités `systemd` ; leur présence dans Git ne prouve ni installation ni réception par un responsable. Aucun webhook n’a été appelé pendant cette implémentation.

## Collecte et alertes

Un collecteur d’exploitation autorisé relève les événements du fournisseur Auth, de GitHub/Cloudflare, des fonctions Edge et des historiques ERP. Il écrit atomiquement `/var/lib/coco-monitor/signals.json`, propriétaire `coco-backup`, permissions 0600, avec ce contrat :

```json
{"version":1,"observed_at":"2026-11-07T00:00:00+00:00","counts":{"privileged_role_change":0,"mfa_removed":0,"sensitive_export":0,"auth_denial":0,"ai_budget_rejected":0,"backup_failed":0,"certificate_expiring":0,"retention_failed":0,"monitor_failed":0}}
```

Le fichier contient uniquement des compteurs agrégés, jamais d’e-mail, nom, objet métier, adresse IP, contenu de document, secret ou jeton. Chaque fenêtre de collecte doit être bornée et enregistrer son dernier curseur en interne pour ne pas rejouer les mêmes événements. Le collecteur doit appliquer les seuils approuvés : par exemple, ne pas qualifier chaque refus Auth isolé d’incident. L’application conserve les détails nécessaires dans les journaux protégés existants ; ils ne passent pas dans l’alerte.

`python3 scripts/coco-operations.py signals --file <fichier>` vérifie le contrat et refuse un relevé de plus de deux heures. `--send-alert` est un choix explicite ; il utilise uniquement la destination existante `COCO_ALERT_WEBHOOK_URL`, HTTPS sans identifiants dans l’autorité, sans redirection et avec une échéance de cinq secondes. La charge transmise contient seulement `service`, `event`, `count`, `time`. Le journal local n’imprime jamais l’URL ni une erreur réseau brute. Une destination absente ne prouve pas qu’une alerte a été reçue.

Les unités `operations/systemd/coco-security-monitor.*` restent des modèles à installer après raccordement du collecteur et du destinataire. L’exploitation doit vérifier une alerte factice de bout en bout et son acquittement, puis surveiller aussi l’absence de relevé et la panne de l’ordonnanceur. Aucun canal de messagerie personnel n’est contacté automatiquement par ce dépôt.

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
