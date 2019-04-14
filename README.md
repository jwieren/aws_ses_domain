## Use Gmail with an email of your own domain

This module is inspired by [Use GMail with your own domain for free thanks to Amazon SES & Lambda](http://www.daniloaz.com/en/use-gmail-with-your-own-domain-for-free-thanks-to-amazon-ses-lambda/),
this terraform code will configure AWS SES service to act as a mail server for your domain, which
can forward emails on to an external mail host like gmail.

AWS SES is configured to act as your mail server by appropriate Route53 records, and a
[receipt rule](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/receiving-email-receipt-rules.html).
When an email is received, the receipt rule determines what SES should do with it.  In this
case, the email is written to S3, and then a lambda is executed to read the email from
S3, and use SES again to send to your external email address.

*Example usage of this module*:

```
module "ses_example_com_domain" {
  source = "./ses_domain"

  domain                    = "example.com"
  lambda_bucket             = "lambda.example.com"
  email_bucket              = "emails.example.com"
  alarms_email              = "my_email@gmail.com"
  verified_sender_email     = "me@example.com"
  receipt_rule_target_email = "me@example.com"
  destination_email         = "my_email@gmail.com"
  lambda_ses_func_name      = "ses-forwarder-example-com"
}

output "ses_email_smtp_secret" {
  value = "${module.ses_email.smtp_secret}"
  sensitive = true
}

output "ses_email_smtp_access_key" {
  value = "${module.ses_email.smtp_access_key}"
}

```

The reason for the `verified_sender_email` is due to a quirk of AWS SES,
where the `From:` header of any email sent through SES must be a
[SES verified email address](https://docs.aws.amazon.com/ses/latest/DeveloperGuide/verify-email-addresses.html).

Use `terraform output` to display the credentials required when
setting up an smtp server in your gmail account.

This code will also set up a cloudwatch alarm to alert you
when your SES lambda is failing, which can be useful to let
you know that you might be missing emails.

*TODO*:
- Retry failed lambda execution (currently email message will remain in S3 until lifecycle removes it)

