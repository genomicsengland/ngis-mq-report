#!/usr/bin/env python3
from modules import get_profile, send_email
from string import Template
from sqlalchemy import create_engine
import pandas as pd
import sys

conns = get_profile.getProfile(items = ['indx_con'])

# psycopg2 connection string template
databaseStringTemplate = 'postgresql+psycopg2://$user:$password@$host:$port/$database'

# generate indx bd connection string
indx_db_connection_string = Template(databaseStringTemplate).safe_substitute({**conns, "database": "metrics"})

e = create_engine(indx_db_connection_string, echo=False)

# read latest reports and recipients query
latest_reports = pd.read_sql('select r.first_name, r.email, r.recipient_type, r.glh, f.path from ngis_mq_results.recipient r left join ngis_mq_results.latest_reports f on r.glh = f.glh where r.glh is not null;', e)

#bug out if any blank entires in path
if any([x == '' for x in latest_reports.path]):
    print('Not all GLHs have a DQ report to send, not sending any emails')
    sys.exit(1)

# group data by glh and read in message template
d = latest_reports.groupby('glh')
body_template = send_email.read_template('message_template.html')

def greetingJoin(l):
    # remove empties
    l = [x for x in l if x != '']
    # if nothing there
    if not l:
        return "Hi"
    # or if just one person address directly
    elif len(l) == 1:
        return 'Dear ' + l[0]
    # concatenate together names if multiple
    else:
        return 'Dear ' + ', '.join(l[:-1]) + " and " + l[-1]

# for each group
for g in d:
    # split group recipients by type
    recip_group = g[1].groupby('recipient_type')
    # get 'to' names and emails
    recipient_name = greetingJoin(recip_group.get_group('to').first_name.tolist())
    recipient_to_email = recip_group.get_group('to').email.tolist()
    # try to get 'cc', leave list empty if none present
    try:
        cc_recipients = recip_group.get_group('cc').email.tolist()
    except KeyError:
        cc_recipients = []
    # make body
    body = body_template.substitute(RECIPIENT_NAME = recipient_name, GLH_NAME = g[0]) 
    # send the email
    send_email.send_email(recipient_to_email,
                'Genomics Medicine Service DQ Report',
                body,
                cc_recipients = cc_recipients,
                attachments = [g[1].path.iloc[0]],
                reply_to = ['DO_NOT_REPLY@genomicsengland.co.uk'])
    print('Sent email for %s GLH to %s' % (g[0], ';'.join(recipient_to_email)))

