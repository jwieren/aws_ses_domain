data "aws_caller_identity" "current" {}

resource "aws_route53_zone" "email_domain" {
  name = "${var.domain}"
}

resource "aws_ses_domain_identity" "ses_domain" {
  domain = "${var.domain}"
}

resource "aws_ses_domain_mail_from" "email_from_domain" {
  domain           = "${aws_ses_domain_identity.ses_domain.domain}"
  mail_from_domain = "mail.${aws_ses_domain_identity.ses_domain.domain}"
}

resource "aws_ses_domain_dkim" "ses_dkim_domain" {
  domain = "${aws_ses_domain_identity.ses_domain.domain}"
}

# For sending MX Record
data "aws_region" "current" {}

# Route53 MX record
resource "aws_route53_record" "ses_from_domain_mx_rec" {
  zone_id = "${aws_route53_zone.email_domain.id}"
  name    = "${aws_ses_domain_mail_from.email_from_domain.mail_from_domain}"
  type    = "MX"
  ttl     = "600"

  records = [
    "10 feedback-smtp.${data.aws_region.current.name}.amazonses.com"
  ]
}

resource "aws_route53_record" "ses_domain_mx_rec" {
  zone_id = "${aws_route53_zone.email_domain.id}"
  name    = "${aws_ses_domain_identity.ses_domain.domain}"
  type    = "MX"
  ttl     = "600"

  records = [
    "10 inbound-smtp.${data.aws_region.current.name}.amazonaws.com"
  ]
}

resource "aws_route53_record" "ses_from_domain_spf_txt_rec" {
  zone_id = "${aws_route53_zone.email_domain.id}"
  name    = "${aws_ses_domain_mail_from.email_from_domain.mail_from_domain}"
  type    = "TXT"
  ttl     = "600"

  records = [
    "v=spf1 include:amazonses.com -all"
  ]
}

resource "aws_route53_record" "ses_domain_verification_txt_rec" {
  zone_id = "${aws_route53_zone.email_domain.id}"
  name    = "_amazonses.${aws_ses_domain_identity.ses_domain.id}"
  type    = "TXT"
  ttl     = "600"

  records = [
    "${aws_ses_domain_identity.ses_domain.verification_token}"
  ]
}

resource "aws_route53_record" "ses_dkim_domain_verification_txt_rec" {
  count   = 3
  zone_id = "${aws_route53_zone.email_domain.id}"
  name    = "${element(aws_ses_domain_dkim.ses_dkim_domain.dkim_tokens, count.index)}._domainkey.${aws_ses_domain_identity.ses_domain.id}"
  type    = "CNAME"
  ttl     = "600"

  records = [
    "${element(aws_ses_domain_dkim.ses_dkim_domain.dkim_tokens, count.index)}.dkim.amazonses.com"
  ]
}

resource "aws_s3_bucket" "emails" {
  bucket = "${var.email_bucket}"
  acl    = "private"

  lifecycle_rule {
    id         = "email_lifecycle_rule"
    enabled    = true
    expiration = {
      days = "${var.email_bucket_expiration}"
    }
  }
}

resource "aws_s3_bucket" "lambda" {
  bucket = "${var.lambda_bucket}"
  acl    = "private"
}

locals {
  lambda_source_file = "lambda.py"
  lambda_zip         = "lambda.zip"
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/${local.lambda_zip}"

  source {
    content  = "${file("${path.module}/${local.lambda_source_file}")}"
    filename = "${local.lambda_source_file}"
  }
}

resource "aws_s3_bucket_object" "ses_lambda" {
  bucket = "${var.lambda_bucket}"
  key    = "${var.lambda_ses_func_name}/${local.lambda_zip}"
  source = "${path.module}/${local.lambda_zip}"
  etag   = "${data.archive_file.lambda_zip.output_base64sha256}"
}

resource "aws_lambda_function" "ses_forwarder" {
  function_name    = "${var.lambda_ses_func_name}"
  s3_bucket        = "${var.lambda_bucket}"
  s3_key           = "${aws_s3_bucket_object.ses_lambda.id}"
  handler          = "lambda.lambda_handler"
  runtime          = "python3.6"
  source_code_hash = "${aws_s3_bucket_object.ses_lambda.etag}"
  role             = "${aws_iam_role.lambda_exec.arn}"

  environment {
    variables = {
      VERIFIED_FROM_EMAIL = "${var.verified_sender_email}"
      SES_INCOMING_BUCKET = "${aws_s3_bucket.emails.bucket}"
      EMAIL_BUCKET_PATH   = ""
      MSG_TARGET          = "${var.verified_sender_email}"
      MSG_TO_LIST         = "${var.destination_email}"
    }
  }
}

# IAM role which dictates what other AWS services the Lambda function
# may access.
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "lambda_ses_forwarder_policy" {
  name        = "lambda-${var.lambda_ses_func_name}-policy"
  path        = "/"
  description = "A policy for the Lambda SES Forwarder to operate"

  policy = <<EOF
{
   "Version": "2012-10-17",
   "Statement": [
      {
         "Effect": "Allow",
         "Action": [
            "logs:CreateLogGroup",
            "logs:CreateLogStream",
            "logs:PutLogEvents"
         ],
         "Resource": "arn:aws:logs:*:*:*"
      },
      {
         "Effect": "Allow",
         "Action": [
             "ses:SendRawEmail",
             "ses:SendEmail"
         ],
         "Resource": "*"
      },
      {
         "Effect": "Allow",
         "Action": [
            "s3:GetObject",
            "s3:PutObject"
         ],
         "Resource": "arn:aws:s3:::${var.email_bucket}/*"
      }
   ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_exec_attach" {
  role       = "${aws_iam_role.lambda_exec.name}"
  policy_arn = "${aws_iam_policy.lambda_ses_forwarder_policy.arn}"
}

resource "aws_ses_receipt_rule_set" "main" {
  rule_set_name = "primary-rules"
}

resource "aws_ses_active_receipt_rule_set" "main" {
  rule_set_name = "${aws_ses_receipt_rule_set.main.rule_set_name}"
}

# Add a header to the email and store it in S3
resource "aws_ses_receipt_rule" "store" {
  name          = "store"
  rule_set_name = "${aws_ses_receipt_rule_set.main.rule_set_name}"
  recipients    = ["${var.receipt_rule_target_email}"]
  enabled       = true
  scan_enabled  = true

  add_header_action {
    header_name  = "Custom-Header"
    header_value = "Added by SES"
    position     = 1
  }

  s3_action {
    bucket_name = "${var.email_bucket}"
    position    = 2
  }

  lambda_action {
    function_arn    = "${aws_lambda_function.ses_forwarder.arn}"
    invocation_type = "Event"
    position        = 3
  }

  depends_on = [
    "aws_s3_bucket_policy.emails",
    "aws_lambda_permission.ses"
  ]
}

data "aws_iam_policy_document" "s3_email_access_policy" {
  statement {
    sid    = "${var.lambda_ses_func_name}-write-email-permission"
    effect = "Allow"

    principals {
      identifiers = ["ses.amazonaws.com"]
      type        = "Service"
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.emails.arn}/*"]

    condition {
      test     = "StringEquals"
      values   = ["${data.aws_caller_identity.current.account_id}"]
      variable = "aws:Referer"
    }
  }
}

resource "aws_s3_bucket_policy" "emails" {
  bucket = "${aws_s3_bucket.emails.id}"
  policy = "${data.aws_iam_policy_document.s3_email_access_policy.json}"
}

resource "aws_lambda_permission" "ses" {
  statement_id   = "${var.lambda_ses_func_name}-allow-ses-execution"
  action         = "lambda:InvokeFunction"
  function_name  = "${aws_lambda_function.ses_forwarder.function_name}"
  principal      = "ses.amazonaws.com"
  source_account = "${data.aws_caller_identity.current.account_id}"
}

resource "aws_iam_access_key" "smtp_access_key" {
  user = "${aws_iam_user.smtp_user.name}"
}

resource "aws_iam_user" "smtp_user" {
  name = "smtp.${var.domain}"
  path = "/"
}

resource "aws_iam_user_policy" "smtp_user_policy" {
  name = "smtp-user-${var.domain}-policy"
  user = "${aws_iam_user.smtp_user.name}"

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ses:SendRawEmail"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_cloudwatch_metric_alarm" "lambda_error" {
  alarm_name          = "${var.lambda_ses_func_name}-execution-errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = "1"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "60"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "${var.lambda_ses_func_name} execution alarm"
  treat_missing_data  = "ignore"

  insufficient_data_actions = [
    "${aws_sns_topic.alarms.arn}",
  ]

  alarm_actions = [
    "${aws_sns_topic.alarms.arn}",
  ]

  ok_actions = [
    "${aws_sns_topic.alarms.arn}",
  ]

  dimensions {
    FunctionName = "${aws_lambda_function.ses_forwarder.function_name}"
    Resource     = "${aws_lambda_function.ses_forwarder.function_name}"
  }
}

resource "aws_sns_topic" "alarms" {
  name            = "${var.lambda_ses_func_name}-alarms-topic"
  delivery_policy = <<EOF
{
  "http": {
    "defaultHealthyRetryPolicy": {
      "minDelayTarget": 20,
      "maxDelayTarget": 20,
      "numRetries": 3,
      "numMaxDelayRetries": 0,
      "numNoDelayRetries": 0,
      "numMinDelayRetries": 0,
      "backoffFunction": "linear"
    },
    "disableSubscriptionOverrides": false,
    "defaultThrottlePolicy": {
      "maxReceivesPerSecond": 1
    }
  }
}
EOF

  provisioner "local-exec" {
    command = "aws sns subscribe --region ${data.aws_region.current.name} --topic-arn ${self.arn} --protocol email --notification-endpoint ${var.alarms_email}"
  }
}
