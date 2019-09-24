#-- TODO: test this as can't really test as insufficient data in it
#-- TODO: particularly bits around removal of cancelled rule people
#-- script to generate ngis mq reports per GLH
rm(list = objects())
options(stringsAsFactors = FALSE,
	scipen = 200)
library(wrangleR)
library(RPostgreSQL)
library(openxlsx)
library(slackr)

#-- get profile data
p <- getprofile(c("indx_con", "ngis_slave_db", "slack_api_token"), file = '.gel_config')

#-- set up Slack connection
#-- slack_channel = "simon-test"
slack_channel = "testathon-is-on"
slackr_setup(channel = slack_channel, 
             incoming_webhook_url="https://hooks.slack.com/services/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",
             api_token = p[['slack_api_token']])

#-- Run the DQ rules
dq_commands <- list(
	'tests' = 'python ngis_mq.py RunDQTests',
	'metrics' = 'python ngis_mq.py RunDQMetrics',
	'refresh_ID' = 'python ngis_mq.py RefreshIDTable',
	'usertab' = 'python ngis_mq.py writeUserTab'
)
dq_output <- list()
for(i in names(dq_commands)){
	#-- run the different dq commands in system, needs to be specified that bash terminal
	system(paste('/bin/bash -c',
			shQuote(paste('cd ../ngis-mq && source venv/bin/activate &&', dq_commands[[i]]))))
	dq_output[[i]] <- readLines('../ngis-mq/log/last-run.log')
}

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
d <- dbGetQuery(res_db_con, '
select organisation_id as organisation
	,referral_link as "Test order link"
	,referral_id as "Referral ID"
	,nhs_chi_number as "Patient\'s NHS Number"
	,patient_date_of_birth as "Patient\'s date of birth"
	,upper(person_first_name) as "Patient\'s first name"
	,upper(person_family_name) as "Patient\'s surname"
	,upper(patient_administrative_gender) as "Patient\'s gender"
	,glh_test_id as "Rule ID"
	,glh_description as "Rule description"
	,resolution_guidance as "Resolution guidance"
	,includes_csv_data as "Includes data from csv?"
	,delays_test_order as "Will block test order?"
	,test_de_datetime as "Failed rule datetime"
	,last_updated_by as "Test order last amended by"
	,last_updated_on as "Test order last amended"
from ngis_mq_results.vw_dq_report_table
where test_result = false and glh_report = \'Y\'
;')

#-- get rule descriptions for both NGIS and DDF rule failures
rules <- dbGetQuery(res_db_con, '
select glh_test_id as "Rule ID"
	,glh_description as "Rule description"
	,resolution_guidance as "Resolution guidance"
	,includes_csv_data as "Includes data from csv"
	,delays_test_order as "Delays the test order"
from ngis_mq_results.test_type
where glh_report in (\'Y\')
order by glh_test_id
;')

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

#-- for those participants that are failing the 'referral is cancelled' rule, want to report that result but not any other rule results
cancelled_rule <- "ngis_rule_000"
cancelled_referral_ids <- d$`Referral ID`[d$`Rule ID` == cancelled_rule] 
d <- d[(!d$`Referral ID` %in% cancelled_referral_ids) | (d$`Referral ID` %in% cancelled_referral_ids & d$`Rule ID` == cancelled_rule), ]

#-- during testing only want to report on those rule failures associated with data entered by GLHs (not GEL)
#-- best way is to limit data to NHS numbers set aside for beta and UAT testing
glh_nhs_numbers <- readLines('valid_test_nhs_numbers.txt')
d <- d[d$`Patient's NHS Number` %in% glh_nhs_numbers,]

#-- replace NAs in organisation with 'unknown'
#-- needed early on as not getting a lot of organisations coming through
#-- d$organisation[is.na(d$organisation)] <- 'unknown'

#-- make table of rule failures per organisation and rule
d_t <- setNames(as.data.frame(table(d$`Rule ID`, d$organisation)),
				 c("Rule ID", "organisation", "Number of failures")
				 )
d_t <- merge(d_t, rules, by = "Rule ID", all.x = T)

#-- wrapper function to create a worksheet with particular formatting
write_xlsx <- function(t, d, fn){
	# creates xlsx workbook
	# header styling and cell styling
	hs1 <- createStyle(fgFill = "#4F81BD", halign = "LEFT", textDecoration = "Bold", border = "Bottom", fontColour = "white")
	cs1 <- createStyle(wrapText = TRUE, halign = 'LEFT', valign = 'top')
	wb <- createWorkbook() 
	# add the worksheets
	addWorksheet(wb, sheetName='Rule Summary')
	addWorksheet(wb, sheetName='Rule Results')
	addWorksheet(wb, sheetName='Rule Descriptions')
	# set the col widths (either manual or auto)
	setColWidths(wb, 1, 1:ncol(t), c(15, 15, 15, 70, 70, 20, 20))
	setColWidths(wb, 2, 1:ncol(d), 'auto')
	setColWidths(wb, 3, 1:ncol(rules), c(15, 70, 70, 20))
	# freeze the top row of the spreadsheet
	freezePane(wb, 1, firstRow = TRUE)
	freezePane(wb, 2, firstRow = TRUE)
	freezePane(wb, 3, firstRow = TRUE)
	# change orientation to landscape
	pageSetup(wb, 1, orientation = 'landscape', scale = 100)
	pageSetup(wb, 2, orientation = 'landscape', scale = 75)
	pageSetup(wb, 3, orientation = 'landscape', scale = 100)
	# add in the data and set the headerstyles
	writeData(wb, 'Rule Summary', t, headerStyle = hs1)
	writeData(wb, 'Rule Results', d, headerStyle = hs1)
	writeData(wb, 'Rule Descriptions', rules, headerStyle = hs1)
	# add the cell styles to just 1st and 3rd sheets (where we want wrapping)
	addStyle(wb, 1, style = cs1, rows = 2:(nrow(t) + 1), cols = 1:ncol(t), gridExpand = TRUE)
	addStyle(wb, 3, style = cs1, rows = 2:(nrow(rules) + 1), cols = 1:ncol(rules), gridExpand = TRUE)
	# make the hyperlinks and overwrite the relevant data
	#removing this for the moment as excel can't cope with SSO of TOMS
	#links  <-  d$`Test order link`
	#names(links) <- rep("Test order link", length(links))
	#class(links) <- "hyperlink"
	#writeData(wb, 2, x = links, startCol = which(colnames(d) == "Test order link"), startRow = 2)
	# write out the workbook
	saveWorkbook(wb, fn, overwrite = TRUE)
}

#-- make dataframe to accommodate latest report details
latest_reports <- data.frame('glh' = character(), 'path' = character())

#-- make a timestamp folder in cdt_share
tstmp <- format(Sys.time(), '%Y-%m-%d_%H%M')
#-- fldr <- paste0('/Users/simonthompson/scratch/dq-report/', tstmp)
fldr <- paste0('/cdt_share/cdt/dq-report/', tstmp)
dir.create(fldr)
#-- for each GLH
for(glh in unique(glhs$glh)){
	#-- get all organisations
	orgs <- unique(glhs$organisation[glhs$glh == glh])
	#-- create the dq report
	fn <- paste0(fldr, '/dq-report-', gsub(".", "-", make.names(glh), fixed = T), '-', tstmp, '.xlsx')
	d_org <- d[d$organisation %in% orgs,]
	t_org <- d_t[d_t$organisation %in% orgs & d_t$`Number of failures` > 0,]
	write_xlsx(t_org, d_org, fn)
	latest_reports[nrow(latest_reports) + 1, ] <- c(glh, fn)
}

#-- zip together everything
zip_fn = paste0("dq-report-", tstmp, ".zip")
system(paste("cd", fldr, "&& zip -R", zip_fn, "'*.xlsx'"))

#-- upload latest_reports to index db
dbWriteTable(res_db_con, c('ngis_mq_results', 'latest_reports'), latest_reports, overwrite = TRUE, row.names = FALSE)

#-- write the last run logs to Slack
for(i in names(dq_output)){
	txt = paste(dq_output[[i]], collapse = '\n')
	slackr_msg(paste('*DQ Report Results - ', i, ':*\n```', txt, '```'), channel = slack_channel)
}

#-- upload zip file to slack channel
slackr_upload(paste0(fldr, '/', zip_fn),
				title = 'DQ Report',
				initial_comment = 'ZIP of DQ Report',
				channels = slack_channel,
				api_token = p[['slack_api_token']])

dbdisconnectall()
