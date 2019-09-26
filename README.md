# NGIS MQ Reports

The contents of this repository generate DQ reports by initiating various ETLs in `ngis_mq`, formatting the results into Excel spreadsheets, and circulating to GLHs and other recipients.

The scheduling is controlled by [a Jenkins job.](https://cln-prod-jenkins.gel.zone/job/cdt/job/cdt-jobs/job/dq-report/)

## `ngis-mq-report-per-glh.r`

This script starts off by kicking off the various ETLs in `ngis_mq` that need to be run regularly. It then generates DQ report spreadsheets shwoing the results of those ETLs for each GLH. The spreadsheets are saved to `cdt_share` and sent to Slack before being distributed to various recipients by `distribute_reports.py` (as dictated by the `ngis_mq_results.recipient` table). The details of the latest reports are sent to the `ngis_mq_results.latest_reports` table.

During testing GLHs were given a set of test NHS numbers that could be used. The DQ report is configured to only use referrals containing these NHS numbers in its output (to avoid including test referrals created by GEL staff). The list of valid NHS numbers to be reported on is held in `valid_test_nhs_numbers.txt`.

There is a dependancy on `openxlsx` to make the spreadsheets. This can only be installed on newer versions of R. To have this run on query it's advisable to install a separate instance of R. [This GitHub project](https://github.com/DominikMueller64/install_R_source) allows you to do this. Once installed then you'll need to install `wrangleR`, `openxlsx` and `RPostgreSQL` and all their dependencies into that new version of R.

Details on how to install the latest version of wrangleR are [available on Confluence](https://cnfl.extge.co.uk/display/CDT/Code+Snippets#CodeSnippets-BuildnewversionofwrangleR).

## `ngis-mq-report-all.r`

This script generates a single spreadsheet showing the current picture of the DQ report, passes and fails, for all GLHs in a single spreadsheet. The output is saved to `cdt_share` and sent to the Slack channel.

## `distribute_reports.py`

This script provides the functionality to send emails to certain recipients using a message template to compose them. It connects to the relevant Microsoft Exchange Server and sends emails via this.

* `modules.get_profile.py` - gets relevant configuration details from the `.gel_config` file;
* `modules.send_email.py` - provides functions for connecting to the Microsoft Exchange Server, generating emails from templates and adding attachments;
* `message_template.html` - the message template that accompanies the email. This is eventually turned into a `Template` object so can hold placeholders for where names etc. can be substituted per email.

# Common Tasks

* **Don't send to a certain person** - if permanent, remove them from `ngis_mq_results.recipient`. If temporary, remove the glh from their entry and reinstate when ready to send again.
* **Stop DQ report all together** - change Jenkins job so it's not a scheduled job.
* **Test an individual rule** - clone everything to local and create a `metrics.ngis_mq_results` schema on your local postgres. Change `local_config.py` so that the `res_db` is pointing to that local database. Then run `RecreateResultsDB` to create all the tables needed. You can then run just a single test and check it's output by looking at `ngis_mq_results.vw_dq_report_table`.
* **Change rule config** - to change description, name, whether rule goes into report etc., **don't change `ngis_mq_results.test_type`**, edit the docstring of the rule function accordingly (how it ends up in `ngis_mq_results.test_type` is how it is found in the dosctring so just copy from another rule if need be), push/pull changes etc. When the DQ report next runs the details of `ngis_mq_results.test_type` will be updated accordingly.
* **Generate the reports but don't send out the output** - comment out lines ~185 & ~194 (runs the system command to trigger `distribute_reports.py`, and sends the output of that to Slack) in `ngis_mq_report-per-glh.r` then start the jenkins job.
