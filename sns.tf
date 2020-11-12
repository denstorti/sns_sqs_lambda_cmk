resource "aws_sns_topic" "user_updates" {
  name              = "user-updates-topic"
  kms_master_key_id = aws_kms_key.sns.key_id

}

resource "aws_kms_key" "sns" {
  description             = "KMS key SNS"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.sns.json

}

resource "aws_kms_alias" "sns" {
  name          = "alias/my-sns"
  target_key_id = aws_kms_key.sns.key_id
}

data "aws_iam_policy_document" "sns" {

  statement {
    effect  = "Allow"
    actions = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = [var.kms_admin_arn]
    }

    resources = ["*"]

  }

}