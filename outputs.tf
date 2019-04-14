output "smtp_secret" {
  value = "${aws_iam_access_key.smtp_access_key.ses_smtp_password}"
}

output "smtp_access_key" {
  value = "${aws_iam_access_key.smtp_access_key.id}"
}