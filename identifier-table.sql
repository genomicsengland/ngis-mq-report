select p.patient_uid as identifier_uid
	,'patient_uid' as identifier_type
	,r.ordering_entity_uid
from public.referral r
left join public.referral_participant rp
	on rp.referral_uid = r.referral_uid
left join public.patient p
	on rp.patient_uid = p.patient_uid

union

select r.referral_uid as identifier_uid
	,'referral_uid' as identifier_type
	,r.ordering_entity_uid
from public.referral r 

union

select rp.referral_participant_uid as identifier_uid
	,'referral_participant_uid' as identifier_type
	,r.ordering_entity_uid
from public.referral_participant rp 
left join public.referral r 
	on rp.referral_uid = r.referral_uid
	
union 

select r.tumour_uid as identifier_uid
	,'tumour_uid' as identifier_type
	,r.ordering_entity_uid
from public.referral r

union 

select r.ordering_entity_uid as identifier_uid
	,'ordering_entity_uid' as identifier_type
	,r.ordering_entity_uid
from public.referral r 
;
