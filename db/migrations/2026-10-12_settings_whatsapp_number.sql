-- MEEM STORE — support WhatsApp number becomes data, not a hardcoded literal.
-- The value is the number that used to be typed into index.html / category.html /
-- checkout-v2.html, so storefront behaviour is unchanged.
begin;
insert into public.settings (key, value)
values ('whatsapp_number', '249901815039')
on conflict (key) do nothing;
select key, value from public.settings where key = 'whatsapp_number';
commit;
