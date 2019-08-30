with referral_ids as (
	/*referral ids*/
	select i.identifier_uid as referral_uid
		,i.identifier_hr as referral_id
		,i.organisation_uid
	from ngis_mq_results.identifier i 
	left join ngis_mq_results.identifier_type it 
		on it.identifier_type_id = i.identifier_type_id 
	where it.identifier_type = 'referral'
),
organisation_ids as (
	/*organisation ids*/
	select i.identifier_uid as organisation_uid
		,i.identifier_hr as organisation_id
	from ngis_mq_results.identifier i 
	left join ngis_mq_results.identifier_type it 
		on it.identifier_type_id = i.identifier_type_id 
	where it.identifier_type = 'organisation'	
)
select o.organisation_id as organisation
	,r.referral_id as "Referral ID"
	,p.nhs_chi_number as "NHS/CHI Number"
	,p.patient_date_of_birth as "Date of Birth"
	,upper(p.person_first_name) as "Patient First Name"
	,upper(p.person_family_name) as "Patient Surname"
	,upper(p.patient_administrative_gender) as "Gender"
	,concat('https://test-ordering.e2e.ngis.io/test-order/', r.referral_id, '/patient-details') as "Referral Link"
from ngis_mq_results.referral_participant_detail p
left join referral_ids r 
	on r.referral_uid = p.referral_uid
left join organisation_ids o 
	on o.organisation_uid = r.organisation_uid
;
