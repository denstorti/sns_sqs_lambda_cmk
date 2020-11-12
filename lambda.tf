resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = data.aws_iam_policy_document.assume_role_lambda.json
}

resource "aws_lambda_function" "test_lambda" {
  filename      = "lambda_function_payload.zip"
  function_name = "lambda_function_name"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "handler.handler"

  # The filebase64sha256() function is available in Terraform 0.11.12 and later
  # For Terraform 0.11.11 and earlier, use the base64sha256() function and the file() function:
  # source_code_hash = "${base64sha256(file("lambda_function_payload.zip"))}"
  source_code_hash = filebase64sha256("lambda_function_payload.zip")

  runtime = "python3.8"

  kms_key_arn = aws_kms_key.lambda.arn

  environment {
    variables = {
      foo = "bar"
    }
  }
}

resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn = aws_sqs_queue.terraform_queue.arn
  function_name    = aws_lambda_function.test_lambda.arn
}

## KMS KEY
resource "aws_kms_key" "lambda" {
  description             = "KMS key lambda"
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.kms_lambda.json

}

resource "aws_kms_alias" "lambda" {
  name          = "alias/my-lambda"
  target_key_id = aws_kms_key.lambda.key_id
}

data "aws_iam_policy_document" "kms_lambda" {

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


data "aws_iam_policy_document" "assume_role_lambda" {

  statement {
    sid     = "LambdaServiceRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}


## EXECUTION ROLE

resource "aws_iam_role_policy_attachment" "execution_role" {
  role       = aws_iam_role.iam_for_lambda.name
  policy_arn = aws_iam_policy.execution_role.arn
}

resource "aws_iam_policy" "execution_role" {
  name        = "lambda_execution_role"
  path        = "/"
  description = "IAM policy for lambda"

  policy = data.aws_iam_policy_document.execution_role.json
}

data "aws_iam_policy_document" "execution_role" {

  statement {
    sid    = "AllowCWlogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    sid    = "AllowSQSreceive"
    effect = "Allow"
    actions = [
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ReceiveMessage"
    ]
    resources = [aws_sqs_queue.terraform_queue.arn]
  }

  statement {
    sid    = "AllowKMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = [aws_kms_key.sqs.arn]
  }
}