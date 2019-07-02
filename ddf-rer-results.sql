/*selects the rule results for the most recent run 
 *of the case through the rules engine*/
with most_recent_job as (
	select gel_case_reference
		,max(job_id) as job_id
	from rer.worker_jobs
	group by gel_case_reference, job_status
	having job_status = 'Complete'
	)
select j.gel_case_reference as "Referral ID"
    ,r.rule_id as "Test ID"
    ,w.job_completed_datetime as "Failed Rule Datetime"
from rer.outcome_rule r
inner join most_recent_job j
    on r.job_id=j.job_id
inner join rer.worker_jobs w 
	on w.job_id=j.job_id
where rule_outcome in ('FAIL')
;
