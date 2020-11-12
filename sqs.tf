resource "aws_sqs_queue" "terraform_queue" {
  name                              = "terraform-example-queue"
  kms_master_key_id                 = aws_kms_key.sqs.key_id
  kms_data_key_reuse_period_seconds = 60
  policy                            = data.aws_iam_policy_document.sqs.json
}

resource "aws_sns_topic_subscription" "user_updates_sqs_target" {
  topic_arn = aws_sns_topic.user_updates.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.terraform_queue.arn
}

## KMS KEY
resource "aws_kms_key" "sqs" {
  description             = "KMS key SQS"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_sqs.json

}

resource "aws_kms_alias" "sqs" {
  name          = "alias/my-sqs"
  target_key_id = aws_kms_key.sqs.key_id
}


data "aws_iam_policy_document" "kms_sqs" {

  statement {
    sid     = "Admin access"
    effect  = "Allow"
    actions = ["kms:*"]

    principals {
      type        = "AWS"
      identifiers = [var.kms_admin_arn]
    }

    resources = ["*"]
  }

  statement {
    sid     = "Allow SNS"
    effect  = "Allow"
    actions = ["kms:GenerateDataKey*", "kms:Decrypt"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    resources = ["*"]
  }

  statement {
    sid     = "Allow Lambda"
    effect  = "Allow"
    actions = ["kms:Decrypt"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.iam_for_lambda.arn]
    }
    resources = ["*"]
  }

}


data "aws_iam_policy_document" "sqs" {
  statement {
    sid     = "Allow SNS"
    effect  = "Allow"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    resources = ["*"]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"

      values = [
        aws_sns_topic.user_updates.arn
      ]
    }
  }
}