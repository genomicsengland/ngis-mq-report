#!/usr/bin/env python3
import exchangelib
from string import Template
from os.path import basename
from modules import get_profile
import sys

email_config = get_profile.getProfile(items = ['nhs'])

# set up connection to EWS
try:
    c = exchangelib.Credentials(email_config['user'], email_config['password'])
    a = exchangelib.Account('genomics.dataquality@nhs.net', credentials = c, autodiscover = True)
except Exception as e:
    print(e)
    sys.exit(1)

def read_template(filename):
    """
    Returns a Template object comprising the contents of the 
    file specified by filename.
    """
    with open(filename, 'r', encoding='utf-8') as template_file:
        template_file_content = template_file.read()
    return Template(template_file_content)

def send_email(to, subject, body, cc_recipients = [], attachments = [], reply_to = []):
    """
    Sends an email to a list of recipients
    to: list of email address of recipients
    email_from: email address to send from
    subject: subject line of email
    body: body text in html
    attachments: list of filepaths to attachments to include
    reply_to: email address to reply to
    """
    # create the message
    m = exchangelib.Message(
        account = a,
        folder = a.sent,
        subject = subject,
        body = exchangelib.HTMLBody(body),
        to_recipients = to,
        cc_recipients = cc_recipients,
        reply_to = reply_to
    )
    for f in attachments:
        # add in attachment
        with open(f, "rb") as fil:
            f_contents = fil.read()
        attach_file = exchangelib.FileAttachment(name = basename(f), content = f_contents)
        m.attach(attach_file)
    # send the message via the server set up earlier.
    m.send_and_save()
    
