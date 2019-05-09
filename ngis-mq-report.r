#-- script to generate ngis mq reports per GLH
rm(list = objects())
options(stringsAsFactors = FALSE,
	scipen = 200)
library(wrangleR)
library(tidyverse)
library(RPostgreSQL)
library(knitr)
library(rmarkdown)

#-- connect to results db
drv <- dbDriver("PostgreSQL")
p <- getprofile(
				"local_postgres_con"
				  )
res_db_con <- dbConnect(drv,
             dbname = "ngis_mq_results",
             host     = p$host,
             port     = p$port,
             user     = p$user,
             password = p$password)
gr_db_con <- dbConnect(drv,
             dbname = "testing",
             host     = p$host,
             port     = p$port,
             user     = p$user,
             password = p$password)


#-- get latest data from results db
md <- dbGetQuery(res_db_con, "select * from vw_latest_metric_results;")
tr <- dbGetQuery(res_db_con, "select * from vw_latest_test_results;")

#-- identifier table, provides linkage of the different identifier_types to GLHs
id <- dbGetQuery(gr_db_con, paste(readLines("identifier-table.sql"), collapse = " "))

#-- merge in id table on both identifier_uid and identifier_type
md <- merge(md, id, by = c("identifier_uid", "identifier_type"), all.x = T)
tr <- merge(tr, id, by = c("identifier_uid", "identifier_type"), all.x = T)

#-- get rule fails per GLH
test_fails <- split(tr[!tr$test_result,], tr$ordering_entity_uid[!tr$test_result])

#-- render the metrics report for all GLHs
render("ngis-mq-report-all-glhs.rmd", output_format = "word_document")

#-- render individual GLH reports
for(glh in unique(md$ordering_entity_uid)){
	render("ngis-mq-report-per-glh.rmd",
		   output_file = paste0("ngis-mq-report-", glh, ".docx"),
		   output_format = "word_document")
}

#-- zip up the resulting files
#--         zip("waterfall-per-cohort.zip", list.files(".", pattern = "^cohort.*docx"), flags = "-FS")
#--         file.remove(list.files(".", pattern = "^cohort.*docx"))

dbdisconnectall()
