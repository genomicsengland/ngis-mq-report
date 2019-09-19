#-- script to generate some basic counts of referrals per GLH and organisation and send to slack
rm(list = objects())
options(stringsAsFactors = FALSE,
	scipen = 200)
library(wrangleR)
library(RPostgreSQL)

#-- get profile data
p <- getprofile(c("indx_con", "ngis_slave_db", "slack_api_token"), file = '.gel_config')

#-- connect to results db and config db
drv <- dbDriver("PostgreSQL")
res_db_con <- dbConnect(drv,
             dbname = "metrics",
             host     = p$indx_con$host,
             port     = p$indx_con$port,
             user     = p$indx_con$user,
             password = p$indx_con$password)
cfg_db_con <- dbConnect(drv,
             dbname = "ngis_config_beta",
             host     = p$ngis_slave_db$host,
             port     = p$ngis_slave_db$port,
             user     = p$ngis_slave_db$user,
             password = p$ngis_slave_db$password)

#-- get latest data from results db (the DQ report view)
#-- can't use the metrics being generated as they include test referrals
#-- below should cover all referrals and collect as many NHS numbers as possible
#-- only selecting referrals that have at least one person in them with a GLH-reserved NHS number
glh_nhs_numbers <- readLines('valid_test_nhs_numbers.txt')
d <- dbGetQuery(res_db_con, paste0("
select distinct organisation_id as organisation
	,referral_id 
from ngis_mq_results.vw_dq_report_table
where nhs_chi_number in ('",
paste0(glh_nhs_numbers, collapse = "','"),
"');"))

#-- get table of GLH:organisation from config
glhs <- dbGetQuery(cfg_db_con, '
select og.organisational_grouping_name as glh
	,o.organisation_name as organisation
from public.organisational_grouping og 
join public.organisation_organisational_grouping ogg 
	on og.organisational_grouping_uid = ogg.organisational_grouping_uid
join public.organisation o 
	on o.organisation_uid = ogg.organisation_uid
;')

#-- merge glh on to referrals
d <- merge(d, glhs, by = 'organisation', all.x = T)

#-- make df to upload to slack
#-- referrals per GLH
g_df <- setNames(as.data.frame(table(d$glh)),
				 c('GLH', 'Number referrals'))
#-- referrals per ordering entity
o_df <- setNames(as.data.frame(table(d$organisation)),
				 c('Ordering entity', 'Number referrals'))

#-- function to send df to slakc with optional message
send_df_to_slack <- function(d, channel, api_token, msg = NA){
	require(knitr)
	require(slackr)
	slackr_setup(channel = channel, 
				incoming_webhook_url="https://hooks.slack.com/services/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",
				api_token = api_token)
	d <- kable(d, format = 'rst')
	if(!is.na(msg)){
		slackr_msg(msg)
	}
	slackr(d, channel = channel)
}

#-- send the different tables to slack
time_stamp <- format(Sys.time(), '%d %b %Y %H:%M')
send_df_to_slack(o_df, 'ngis-metrics', p$slack_api_token, paste('Number of referrals (using GLH-reserved NHS numbers) per ordering entity', time_stamp))
send_df_to_slack(g_df, 'ngis-metrics', p$slack_api_token, paste('Number of referrals (using GLH-reserved NHS numbers) per GLH', time_stamp))

dbdisconnectall()
