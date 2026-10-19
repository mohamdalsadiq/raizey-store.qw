// Regenerate after upgrading the pinned libphonenumber-js dependency.
import fs from 'node:fs';
import crypto from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const metadata=require('libphonenumber-js/metadata.max.json');
const version=require('libphonenumber-js/package.json').version;
const quote=s=>"'"+String(s).replaceAll("'","''")+"'";
const rows=Object.entries(metadata.countries).map(([country,m])=>{
 const types=(m[11]||[]).filter(t=>Array.isArray(t)&&t[0]).map(t=>({pattern:t[0],lengths:t[1]||m[3]}));
 return '('+[country,m[0],m[2],JSON.stringify({lengths:m[3],types})].map(quote).join(',')+')';
});
const sql=`-- Generated from libphonenumber-js ${version} max metadata (MIT); do not hand-edit numbering plans.
CREATE TABLE IF NOT EXISTS private.phone_country_rules(country text PRIMARY KEY, calling_code text NOT NULL, national_pattern text NOT NULL, rules jsonb NOT NULL);
ALTER TABLE private.phone_country_rules ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.phone_country_rules FROM PUBLIC,anon,authenticated;
INSERT INTO private.phone_country_rules(country,calling_code,national_pattern,rules) VALUES
${rows.join(',\n')}
ON CONFLICT(country) DO UPDATE SET calling_code=EXCLUDED.calling_code,national_pattern=EXCLUDED.national_pattern,rules=EXCLUDED.rules;

CREATE OR REPLACE FUNCTION private.valid_contact_number(p_phone text,p_country text DEFAULT NULL)
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v text:=private.normalize_whatsapp(p_phone); r record; n text; t jsonb;
BEGIN
 IF v IS NULL THEN RETURN NULL; END IF;
 FOR r IN SELECT * FROM private.phone_country_rules WHERE (p_country IS NULL OR country=upper(p_country)) AND v LIKE '+'||calling_code||'%' LOOP
  n:=substr(v,length(r.calling_code)+2);
  IF NOT (r.rules->'lengths') @> to_jsonb(length(n)) OR n !~ ('^(?:'||r.national_pattern||')$') THEN CONTINUE; END IF;
  IF jsonb_array_length(r.rules->'types')=0 THEN RETURN v; END IF;
  FOR t IN SELECT value FROM jsonb_array_elements(r.rules->'types') LOOP
   IF (t->'lengths') @> to_jsonb(length(n)) AND n ~ ('^(?:'||(t->>'pattern')||')$') THEN RETURN v; END IF;
  END LOOP;
 END LOOP;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION private.valid_contact_number(text,text) FROM PUBLIC,anon,authenticated;

CREATE OR REPLACE FUNCTION public.validate_profile_contact()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v text;
BEGIN
 IF TG_OP='INSERT' THEN NEW.whatsapp_number:=private.valid_contact_number(NEW.whatsapp_number);
 ELSIF NEW.whatsapp_number IS DISTINCT FROM OLD.whatsapp_number THEN
  v:=private.valid_contact_number(NEW.whatsapp_number);
  IF v IS NULL THEN RAISE EXCEPTION 'invalid_whatsapp'; END IF;
  NEW.whatsapp_number:=v;
 END IF;
 RETURN NEW;
END $$;
CREATE OR REPLACE FUNCTION public.get_own_onboarding_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
DECLARE v_phone text;
BEGIN
 PERFORM private.assert_session_aal();
 IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
 SELECT whatsapp_number INTO v_phone FROM public.profiles WHERE id=auth.uid();
 RETURN jsonb_build_object('has_whatsapp',private.valid_contact_number(v_phone) IS NOT NULL);
END $$;
DROP FUNCTION IF EXISTS public.complete_whatsapp_onboarding(text);
CREATE OR REPLACE FUNCTION public.complete_whatsapp_onboarding(p_phone text,p_country text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v text;
BEGIN
 PERFORM private.assert_session_aal();
 IF public.is_banned() THEN RAISE EXCEPTION 'access_denied'; END IF;
 IF p_country IS NOT NULL AND (p_country !~ '^[A-Z]{2}$' OR p_country='IL') THEN RAISE EXCEPTION 'invalid_whatsapp_country'; END IF;
 v:=private.valid_contact_number(p_phone,p_country);
 IF v IS NULL THEN RAISE EXCEPTION 'invalid_whatsapp'; END IF;
 UPDATE public.profiles SET whatsapp_number=v WHERE id=auth.uid();
 IF NOT FOUND THEN RAISE EXCEPTION 'profile_missing'; END IF;
 RETURN jsonb_build_object('completed',true);
END $$;
REVOKE ALL ON FUNCTION public.complete_whatsapp_onboarding(text,text) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.complete_whatsapp_onboarding(text,text) TO authenticated,service_role;
CREATE OR REPLACE FUNCTION public.require_order_contact()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF auth.role()='authenticated' THEN
  PERFORM private.assert_session_aal();
  IF NOT EXISTS(SELECT 1 FROM public.profiles p WHERE p.id=auth.uid() AND private.valid_contact_number(p.whatsapp_number) IS NOT NULL) THEN RAISE EXCEPTION 'whatsapp_required'; END IF;
 END IF;
 RETURN NEW;
END $$;
`;
fs.writeFileSync('supabase/migrations/20261019001000_phone_number_country_rules.sql',sql);
const filename=`libphonenumber-max-${version}.js`;
// Omit source-map reference: the production site does not ship development maps.
const bundle=fs.readFileSync('node_modules/libphonenumber-js/bundle/libphonenumber-max.js','utf8').replace(/\/\/# sourceMappingURL=.*$/m,'');
fs.writeFileSync('assets/vendor/'+filename,bundle);
fs.copyFileSync('node_modules/libphonenumber-js/LICENSE','assets/vendor/libphonenumber-LICENSE.txt');
const manifest=JSON.parse(fs.readFileSync('assets/vendor/manifest.json'));manifest[filename]=crypto.createHash('sha256').update(bundle).digest('hex');
fs.writeFileSync('assets/vendor/manifest.json',JSON.stringify(manifest,null,2)+'\n');
console.log(`Generated ${rows.length} country rules and pinned browser bundle ${version}.`);
