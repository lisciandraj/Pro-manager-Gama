create table public.knowledge_articles (
 id uuid primary key default gen_random_uuid(),
 parent_id uuid references public.knowledge_articles(id) on delete restrict,
 slug text unique,
 title text not null check (length(btrim(title)) between 1 and 200),
 body text not null check (length(btrim(body)) between 1 and 100000),
 properties jsonb not null default '[]'::jsonb check (jsonb_typeof(properties)='array' and jsonb_array_length(properties)<=30),
 version integer not null default 1,
 created_by uuid references auth.users(id) on delete set null default auth.uid(),
 updated_by uuid references auth.users(id) on delete set null default auth.uid(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 check (parent_id is distinct from id)
);
create index knowledge_articles_parent_idx on public.knowledge_articles(parent_id);
create index knowledge_articles_created_by_idx on public.knowledge_articles(created_by);
create index knowledge_articles_updated_by_idx on public.knowledge_articles(updated_by);
alter table public.knowledge_articles enable row level security;
revoke all on public.knowledge_articles from anon,authenticated;
grant select,insert,update on public.knowledge_articles to authenticated;
create policy knowledge_read on public.knowledge_articles for select to authenticated
 using ((select private.current_user_role()) in ('administrador','comercial','almacenero'));
create policy knowledge_insert on public.knowledge_articles for insert to authenticated
 with check ((select private.current_user_role())='administrador');
create policy knowledge_update on public.knowledge_articles for update to authenticated
 using ((select private.current_user_role())='administrador')
 with check ((select private.current_user_role())='administrador');

-- Parent relationships are fixed on creation: no cycles or orphaned subarticles.
-- Every update increments a revision used by the editor to detect concurrent edits.
create function private.gama_knowledge_validate() returns trigger
language plpgsql security invoker set search_path='' as $$
declare p jsonb; seen text[]:='{}'; label_key text;
begin
 if tg_op='UPDATE' then
  if new.id is distinct from old.id or new.parent_id is distinct from old.parent_id or new.slug is distinct from old.slug then
   raise exception 'La estructura del artículo no se puede modificar.';
  end if;
  new.created_at:=old.created_at;new.created_by:=old.created_by;new.version:=old.version+1;
 else
  new.version:=1;new.created_at:=now();new.created_by:=auth.uid();
  if new.parent_id is not null and not exists(select 1 from public.knowledge_articles where id=new.parent_id) then
   raise exception 'Artículo principal no encontrado.';
  end if;
 end if;
 new.updated_at:=clock_timestamp();new.updated_by:=auth.uid();
 if jsonb_typeof(new.properties)<>'array' or jsonb_array_length(new.properties)>30 then raise exception 'Propiedades inválidas.';end if;
 for p in select value from jsonb_array_elements(new.properties) loop
  if jsonb_typeof(p)<>'object' or jsonb_typeof(p->'label') is distinct from 'string' or length(btrim(p->>'label')) not between 1 and 80 or coalesce(p->>'type','') not in ('text','number','date','boolean','select') then raise exception 'Propiedades inválidas.';end if;
  label_key:=lower(btrim(p->>'label'));
  if label_key=any(seen) then raise exception 'Cada propiedad debe tener un nombre único.';end if;
  seen:=array_append(seen,label_key);
  if not (p ? 'value') or length(p->>'value')>2000 then raise exception 'Valor de propiedad inválido.';end if;
  if p->>'type'='boolean' and jsonb_typeof(p->'value') is distinct from 'boolean' then raise exception 'Valor booleano inválido.';end if;
  if p->>'type'='number' and jsonb_typeof(p->'value') is distinct from 'number' and p->>'value' is distinct from '' then raise exception 'Valor numérico inválido.';end if;
  if p->>'type' in ('text','date','select') and jsonb_typeof(p->'value') is distinct from 'string' then raise exception 'Valor de texto inválido.';end if;
  if p->>'type'='date' and p->>'value'<>'' then
   if p->>'value' !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Fecha inválida.';end if;
   perform (p->>'value')::date;
  end if;
  if p->>'type'='select' then
   if jsonb_typeof(p->'options') is distinct from 'array' then raise exception 'Opciones inválidas.';end if;
   if jsonb_array_length(p->'options') not between 1 and 100 or exists(select 1 from jsonb_array_elements(p->'options') o where jsonb_typeof(o)<>'string' or length(o#>>'{}') not between 1 and 200) then raise exception 'Opciones inválidas.';end if;
   if p->>'value'<>'' and not (p->'options' @> jsonb_build_array(p->>'value')) then raise exception 'Selecciona una opción válida.';end if;
  end if;
 end loop;
 return new;
end $$;
revoke all on function private.gama_knowledge_validate() from public,anon,authenticated;
create trigger knowledge_validate before insert or update on public.knowledge_articles for each row execute function private.gama_knowledge_validate();

insert into public.knowledge_articles(slug,title,body,properties) values (
'gama-getting-started',
'Bien démarrer avec GAMA ERP',
$guide$# À quoi sert GAMA ERP ?
GAMA centralise les produits, les clients, les fournisseurs et le suivi des opérations : demandes clients, devis, commandes, préparation, livraison, factures internes et paiements. Chaque module affiche les fonctions autorisées pour votre compte.

# 1. Se connecter et se repérer
- Connectez-vous avec votre compte personnel et votre mot de passe.
- Le menu principal regroupe les modules par activité. Utilisez sa recherche pour retrouver un module.
- Sur les grands écrans, la barre latérale permet de passer directement à un autre module.
- Le bouton « Retour au menu » ramène à l’accueil.
- Dans Configuration, choisissez la langue de l’interface : français, espagnol ou anglais. Les noms de produits et les textes rédigés par les utilisateurs conservent leur langue d’origine.
- Déconnectez-vous lorsque vous avez terminé sur un appareil partagé.

# 2. Comprendre les accès
L’administrateur gère la configuration et les comptes. Les commerciaux accèdent aux fonctions commerciales. Les magasiniers utilisent les fonctions de stock et de logistique. Les clients disposent d’un espace limité à leurs opérations autorisées. Le module Knowledge est réservé aux comptes internes ; les administrateurs rédigent et modifient les articles.
Si un module n’apparaît pas, vérifiez vos permissions et demandez à l’administrateur s’il est activé dans Configuration.

# 3. Préparer les données de base
Commencez par les fournisseurs, les produits et les clients.
- Dans Produits, renseignez le nom, la référence, le code-barres, les prix, la TVA et les informations logistiques utiles.
- Le nom, la référence et le code-barres ne doivent pas reprendre ceux d’un autre produit, y compris archivé.
- Un produit importé sans code-barres peut recevoir son code plus tard : ouvrez sa propre ligne avec « Modifier », renseignez le code et enregistrez.
- Dans Clients, vérifiez les coordonnées, l’adresse, l’email, la catégorie tarifaire et le délai de paiement en jours depuis la livraison.
- Dans Fournisseurs, complétez les coordonnées nécessaires aux achats.
- Le module Importer des données permet de charger les fichiers Excel. Vérifiez le résultat de l’import, les doublons signalés et les lignes en erreur avant de recommencer.

# 4. De la demande client au devis
Le client peut préparer une demande depuis son catalogue. Dans « Devis et factures », l’équipe commerciale retrouve les demandes et peut créer le devis associé via le bouton prévu.
Vérifiez les produits, les quantités, les prix, les taxes, les coordonnées et les commentaires avant de transmettre le devis. Un produit indisponible ou une offre spéciale peut nécessiter une modification du devis.
Le client peut accepter le devis dans son espace. Un commercial ou un administrateur peut enregistrer une acceptation reçue en dehors de GAMA. Utilisez cette action uniquement lorsque l’accord du client a réellement été obtenu.

# 5. Commande et réservation de stock
Après acceptation, suivez la commande dans Commandes clients et dans Suivi de dossier. Contrôlez les quantités disponibles et réservées. En cas de stock insuffisant, traitez le besoin d’approvisionnement ou le reliquat indiqué avant de poursuivre.
La réservation affecte la disponibilité du stock ; elle ne signifie pas que les produits ont déjà été livrés.

# 6. Préparer la commande
Dans Préparation des commandes, ouvrez la commande concernée. Préparez les quantités, répartissez les produits dans les cartons et effectuez les contrôles demandés par code-barres.
Corrigez les différences entre les quantités attendues et préparées. Fermez la préparation lorsque les contrôles sont terminés pour transmettre l’opération au transport.

# 7. Expédier et livrer
Dans le TMS, ouvrez l’expédition, contrôlez le chargement des colis et suivez les étapes proposées. À la livraison, renseignez les informations réelles et recueillez la signature du client avant de valider la preuve de livraison.
En cas de refus, de livraison partielle ou de problème, indiquez la situation réelle et utilisez les actions disponibles ; ne confirmez pas une livraison qui n’a pas eu lieu.
L’historique du TMS permet de retrouver les événements de transport. Les clients peuvent consulter leurs propres preuves dans « Mes livraisons ».

# 8. Facture interne et facture externe
La preuve de livraison validée par le transporteur et signée par le client déclenche la génération de la facture interne lorsque les conditions du dossier sont remplies. Consultez la facture et le suivi du dossier pour vérifier le résultat.
La facture interne sert au suivi dans GAMA. La facture électronique officielle reste émise dans le logiciel de facturation externe utilisé par l’entreprise. Rattachez sa référence au dossier avec les fonctions prévues.

# 9. Enregistrer les paiements
Dans Paiements clients, ouvrez la facture et vérifiez le montant facturé, les encaissements et le solde restant. Enregistrez les paiements réellement reçus avec leur date, leur montant, leur moyen et leur référence.
Le délai de paiement de la fiche client sert au calcul de l’échéance depuis la livraison. Une alerte orange prévient dans les 7 jours précédant l’échéance ; une alerte rouge signale son dépassement. Les relances peuvent être préparées depuis le module : vérifiez le destinataire et le texte avant l’envoi.
Un règlement partiel laisse un solde ouvert. Le paiement constitue la dernière étape de suivi pour clôturer le dossier lorsque toutes les autres étapes sont terminées.

# 10. Achats et réception des marchandises
En cas de besoin de stock, préparez l’achat auprès du fournisseur. Lors de la réception, contrôlez les produits et les quantités effectivement reçues, puis validez la réception dans le module prévu.
Utilisez les mouvements de stock ou corrections appropriés pour tracer les écarts ; évitez de recréer un produit pour corriger une quantité.

# 11. Surveiller les opérations
Consultez le tableau de bord, le contrôle commercial et logistique et les notifications pour repérer les blocages, retards, besoins de stock et paiements à suivre.
Le module Suivi de dossier rassemble les étapes liées à une même opération. Ouvrez le document concerné depuis ce suivi pour comprendre l’étape restante.

# 12. Utiliser cette base de connaissances
- Recherchez un mot dans le titre, le contenu ou les propriétés des articles.
- Parcourez l’arborescence et ouvrez les sous-articles pour accéder aux procédures détaillées.
- Les administrateurs peuvent créer un article principal ou un sous-article depuis une page existante.
- Ajoutez des propriétés pour préciser le service, le responsable, une date, un nombre ou une catégorie.
- Utilisez les titres, listes et passages en gras pour rendre les instructions lisibles, puis contrôlez l’aperçu et enregistrez.
- Si une autre personne modifie le même article, GAMA bloque l’écrasement de sa version : copiez vos changements avant de recharger la page.

# En cas de difficulté
Si le scanner reste noir sur iPhone, vérifiez l’autorisation d’accès à l’appareil photo. Essayez dans Safari ; après avoir corrigé l’autorisation, fermez puis rouvrez GAMA depuis l’icône de l’écran d’accueil.
Si un enregistrement échoue, conservez le message d’erreur et la référence du document. Vérifiez les champs obligatoires et votre connexion, puis demandez de l’aide à l’administrateur. Avant de réessayer une opération, contrôlez si elle a déjà été enregistrée.
$guide$,
'[{"label":"Type","type":"select","options":["Guide","Procédure","FAQ"],"value":"Guide"},{"label":"Public","type":"text","value":"Tous les comptes internes"},{"label":"Langue","type":"text","value":"Français"}]'::jsonb
);
