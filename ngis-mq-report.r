#-- script to generate ngis mq reports per GLH
rm(list = objects())
options(stringsAsFactors = FALSE,
	scipen = 200)
library(wrangleR)
library(RPostgreSQL)
library(openxlsx)

#-- connect to results db
drv <- dbDriver("PostgreSQL")
p <- getprofile("indx_con")
res_db_con <- dbConnect(drv,
             dbname = "metrics",
             host     = p$host,
             port     = p$port,
             user     = p$user,
             password = p$password)

#-- get latest data from results db
md <- dbGetQuery(res_db_con, "select * from ngis_mq_results.vw_latest_metric_results;")
tr <- dbGetQuery(res_db_con, "
	select identifier_hr
		,identifier_type
		,case
			when test_result = true then 'PASS'
			when test_result = false then 'FAIL'
			else null
		end as rule_result
		,glh_test_id as rule
		,test_datetime as rule_datetime
		,glh
	from ngis_mq_results.vw_latest_test_results
	where glh_report in ('Y')
	order by glh_test_id, identifier_hr
	;")

#-- get rule descriptions
rules <- dbGetQuery(res_db_con, "
	select glh_test_id as rule
		,glh_description as description
	from ngis_mq_results.test_type
	where glh_report in ('Y')
	order by glh_test_id
	;")

#-- wrapper function to create a worksheet with particular formatting
write_xlsx <- function(d, fn){
	# creates xlsx workbook
	# header styling
	r <- rules[rules$rule %in% d$rule,]
	hs1 <- createStyle(fgFill = "#4F81BD", halign = "LEFT", textDecoration = "Bold", border = "Bottom", fontColour = "white")
	cs1 <- createStyle(wrapText = TRUE, halign = 'LEFT', valign = 'top')
	wb <- createWorkbook() 
	addWorksheet(wb, sheetName='Rule Failures')
	addWorksheet(wb, sheetName='Rule Descriptions')
	addWorksheet(wb, sheetName='Rule Results')
	setColWidths(wb, 1, 1:ncol(d), 'auto')
	setColWidths(wb, 2, 1:ncol(rules), c(15, 100))
	freezePane(wb, 1, firstRow = TRUE)
	freezePane(wb, 2, firstRow = TRUE)
	writeData(wb, 'Rule Failures', d[d$rule_result %in% c('FAIL'), colnames(d) %in% c("identifier_hr", "identifier_type", "rule")], headerStyle = hs1)
	writeData(wb, 'Rule Descriptions', r, headerStyle = hs1)
	writeData(wb, 'Rule Results', d)
	addStyle(wb, 2, style = cs1, rows = 2:(nrow(r) + 1), cols = 1:ncol(r), gridExpand = TRUE)
	saveWorkbook(wb, fn, overwrite = TRUE)
}

#-- create individual GLH xlsx
for(glh in unique(md$glh)){
	fn <- paste0("gmc-dq-results-", glh, '.xlsx')
	write_xlsx(tr[tr$glh %in% glh, !colnames(tr) %in% c('glh')],fn)
}

#-- zip up the resulting files
#--         zipr("waterfall-per-cohort.zip", list.files(".", pattern = "^cohort.*docx"), flags = "-FS")
#--         file.remove(list.files(".", pattern = "^cohort.*docx"))

dbdisconnectall()
