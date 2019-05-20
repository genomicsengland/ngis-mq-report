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
p <- getprofile("indx_con")
res_db_con <- dbConnect(drv,
             dbname = "metrics",
             host     = p$host,
             port     = p$port,
             user     = p$user,
             password = p$password)


#-- get latest data from results db
md <- dbGetQuery(res_db_con, "select * from ngis_mq_results.vw_latest_metric_results;")
tr <- dbGetQuery(res_db_con, "select * from ngis_mq_results.vw_latest_test_results;")

#-- render the metrics report for all GLHs
render("ngis-mq-report-all-glhs.rmd", output_format = "word_document")

#-- render individual GLH reports
for(glh in unique(md$glh)){
	render("ngis-mq-report-per-glh.rmd",
		   output_file = paste0("ngis-mq-report-", glh, ".docx"),
		   output_format = "word_document")
}

#-- zip up the resulting files
#--         zip("waterfall-per-cohort.zip", list.files(".", pattern = "^cohort.*docx"), flags = "-FS")
#--         file.remove(list.files(".", pattern = "^cohort.*docx"))

dbdisconnectall()
