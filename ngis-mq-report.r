#-- TODO: test this as can't really test as insufficient data in it
#-- TODO: particularly bits around removal of cancelled rule people
#-- script to generate ngis mq reports per GLH
#-- requires an R version that isn't default on Index (see README.md)
#-- run with /usr/local/R/3.5.3/bin/Rscript ngis-mq-report.r 
rm(list = objects())
options(stringsAsFactors = FALSE,
	scipen = 200)
library(wrangleR)
library(RPostgreSQL)
library(openxlsx)
library(slackr)

#-- get profile data
p <- getprofile(c("indx_con", "cdr_auto", "slack_api_token"))

#-- Run the DQ rules
dq_commands <- list(
	'tests' = 'python ngis_mq.py RunDQTests',
	'metrics' = 'python ngis_mq.py RunDQMetrics',
	'refresh_ID' = 'python ngis_mq.py RefreshIDTable',
	'usertab' = 'python ngis_mq.py writeUserTab'
)
dq_output <- lapply(dq_commands, function(x) system(paste('cd ../ngis-mq && source venv/bin/activate &&', x)))

#-- set up Slack connection
slackr_setup(channel = "simon-t", 
             incoming_webhook_url="https://hooks.slack.com/services/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",
             api_token = p[['slack_api_token']])

#-- connect to results db
drv <- dbDriver("PostgreSQL")
res_db_con <- dbConnect(drv,
             dbname = "metrics",
             host     = p$indx_con$host,
             port     = p$indx_con$port,
             user     = p$indx_con$user,
             password = p$indx_con$password)
cdr_db_con <- dbConnect(drv,
             dbname = "central_data_repo",
             host     = p$cdr_auto$host,
             port     = p$cdr_auto$port,
             user     = p$cdr_auto$user,
             password = p$cdr_auto$password)

#-- get latest data from results db (the DQ report view)
d <- dbGetQuery(res_db_con, '
select organisation_id as organisation
	,referral_id as "Referral ID"
	,nhs_chi_number as "NHS/CHI Number"
	,patient_date_of_birth as "Date of Birth"
	,upper(person_first_name) as "Patient First Name"
	,upper(person_family_name) as "Patient Surname"
	,upper(patient_administrative_gender) as "Gender"
	,glh_test_id as "Test ID"
	,glh_description as "Test Description"
	,resolution_guidance as "Resolution Guidance"
	,includes_csv_data as "Includes Data from CSV"
	,test_de_datetime as "Failed Rule Datetime"
	,referral_link as "Referral Link"
	,last_updated_by as "Last Updated By"
	,last_updated_on as "Last Updated On"
from ngis_mq_results.vw_dq_report_table
where test_result = false and glh_report = \'Y\'
;')

#-- get rule descriptions for both NGIS and DDF rule failures
rules <- dbGetQuery(res_db_con, '
	select glh_test_id as "Test ID"
		,glh_description as "Test Description"
		,resolution_guidance as "Resolution Guidance"
		,includes_csv_data as "Includes Data from CSV"
	from ngis_mq_results.test_type
	where glh_report in (\'Y\')
	order by glh_test_id
	;')
ddf_rules <- read.csv("ddf-rule-descriptions.csv", check.names = F)
rules <- rbind(rules, ddf_rules)

#-- get DDF rule failures
ddf_d <- dbGetQuery(cdr_db_con, paste(readLines("ddf-rer-results.sql"), collapse = " "))

#-- get participant details to merge into ddf rule failures
p_details <- dbGetQuery(res_db_con, paste(readLines("proband-details.sql"), collapse = " "))

#-- merge the two together
ddf_d <- merge(ddf_d, p_details, by = "Referral ID", all.x = T)

#-- inner merge of the ddf rules data so now only getting rule failures that should be reported to GLH
ddf_d <- merge(ddf_d, ddf_rules, by = "Test ID", all.y = T)

#-- rbind ddf rule failures onto NGIS MQ rule failures
d <- rbind(d, ddf_d)

#-- for those participants that are failing the 'referral is cancelled' rule, want to report that result but not any other rule results
cancelled_rule <- "ngis_rule_000"
cancelled_referral_ids <- d$`Referral ID`[d$`Test ID` == cancelled_rule] 
d <- d[(!d$`Referral ID` %in% cancelled_referral_ids) | (d$`Referral ID` %in% cancelled_referral_ids & d$`Test ID` == cancelled_rule), ]

#-- replace NAs in organisation with 'unknown'
#-- needed early on as not getting a lot of organisations coming through
d$organisation[is.na(d$organisation)] <- 'unknown'

#-- make table of rule failures per organisation and rule
d_t <- setNames(as.data.frame(table(d$`Test ID`, d$organisation)),
				 c("Test ID", "organisation", "Number of Failures")
				 )
d_t <- merge(d_t, rules, by = "Test ID", all.x = T)

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
	addWorksheet(wb, sheetName='All Rules')
	# set the col widths (either manual or auto)
	setColWidths(wb, 1, 1:ncol(t), c(15, 15, 70, 70, 20))
	setColWidths(wb, 2, 1:ncol(d), 'auto')
	setColWidths(wb, 3, 1:ncol(rules), c(15, 70, 70, 20))
	# freeze the top row of the spreadsheet
	freezePane(wb, 1, firstRow = TRUE)
	freezePane(wb, 2, firstRow = TRUE)
	freezePane(wb, 3, firstRow = TRUE)
	# add in the data and set the headerstyles
	writeData(wb, 'Rule Summary', t, headerStyle = hs1)
	writeData(wb, 'Rule Results', d, headerStyle = hs1)
	writeData(wb, 'All Rules', rules, headerStyle = hs1)
	# add the cell styles to just 1st and 3rd sheets (where we want wrapping)
	addStyle(wb, 1, style = cs1, rows = 2:(nrow(rules) + 1), cols = 1:ncol(rules), gridExpand = TRUE)
	addStyle(wb, 3, style = cs1, rows = 2:(nrow(rules) + 1), cols = 1:ncol(rules), gridExpand = TRUE)
	# make the hyperlinks and overwrite the relevant data
	links  <-  d$`Referral Link`
	names(links) <- rep("Referral Link", length(links))
	class(links) <- "hyperlink"
	writeData(wb, 2, x = links, startCol = which(colnames(d) == "Referral Link"), startRow = 2)
	# write out the workbook
	saveWorkbook(wb, fn, overwrite = TRUE)
}

#-- create individual GLH xlsx
filenames <- c()
tstmp <- format(Sys.time(), '%Y-%m-%d_%H%m')
for(glh in unique(d$organisation)){
	fn <- paste0("gmc-dq-results-", gsub(".", "-", make.names(glh), fixed = T), tstmp, '.xlsx')
	d_glh <- d[d$organisation %in% glh, !colnames(d) %in% c('organisation')]
	t_glh <- d_t[d_t$organisation %in% glh, !colnames(d_t) %in% c('organisation')]
	write_xlsx(t_glh, d_glh, fn)
	filenames <- c(filenames, fn)
}

#-- zip up the resulting files
#--         zipr("waterfall-per-cohort.zip", list.files(".", pattern = "^cohort.*docx"), flags = "-FS")
#--         file.remove(list.files(".", pattern = "^cohort.*docx"))

#-- upload files to slack channel
for(i in filenames){
	slackr_upload(i, title = basename(i), initial_comment = basename(i), channels = "@simon-t", api_token = p[['slack_api_token']])
}

dbdisconnectall()
