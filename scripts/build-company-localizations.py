"""Regenerate the immutable company localization migration seed from reviewed models."""
import json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
path=root/'supabase/migrations/20260919094748_company_identity_localization.sql'
s=path.read_text();start=s.index('-- TEMPLATE_DATA_START');end=s.index('-- TEMPLATE_DATA_END',start)
statements=['-- TEMPLATE_DATA_START (generated from config/localizations/*.json)']
for model in sorted((root/'config/localizations').glob('*.json')):
 data=json.loads(model.read_text());payload=json.dumps(data,ensure_ascii=False,separators=(',',':')).replace("'","''")
 statements.append("insert into private.company_localization_templates(country,template) values ('"+data['country']+"','"+payload+"'::jsonb);")
path.write_text(s[:start]+'\n'.join(statements)+'\n'+s[end:])
