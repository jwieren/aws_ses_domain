variable domain {
  type = "string"
  description = "The route53 domain to create a zone for"
}

variable lambda_bucket {
  type = "string"
  description = "The s3 bucket to contain lambda code"
}

variable email_bucket {
  type = "string"
  description = "The s3 bucket to temporarily store emails"
}

variable alarms_email {
  type = "string"
  description = "Email address to notify when a lambda error occurs"
}

variable verified_sender_email {
  type = "string"
  description = "SES verified email address to be the 'From:' email"
}

variable receipt_rule_target_email {
  type = "string"
  description = "The email address target"
}

variable destination_email {
  type = "string"
  description = "The inbox to forward emails to the target address to"
}

variable lambda_ses_func_name {
  type = "string"
  description = "The name of the lambda to process SNS requests"
}

variable email_bucket_expiration {
  type = "string"
  description = "Number of days to retain an email in the S3 bucket"
  default = "7"
}



