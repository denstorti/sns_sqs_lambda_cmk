# Practical explanation on policies for integrating encrypted (CMK) SNS, SQS, Lambdas

## Overview

Encrypted SNS --> Encrypted SQS --> Encrypted Lambda

## Pre-requisites
- terraform 0.13+
- AWS credentials

## How to deploy
- terraform init
- terraform plan
- terraform apply

### Publishing to SNS

- Publishing: First, the principal publishing messages to the Amazon SNS encrypted topic must have access permission to execute the AWS KMS operations `GenerateDataKey` and `Decrypt`, in addition to the Amazon SNS operation `Publish`
- Publishing SNS must allow `SNS:Subscribe` in its Access Policy to SQS queue

### Integrating SNS and encrypted SQS

- SQS must allow in its Access Policy the SNS topic to send message:

```hcl
data "aws_iam_policy_document" "sqs" {
  statement {
    sid = "Allow SNS"
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
```

- SNS must have `GenerateDataKey` and `Decrypt` permissions in the CMK of the SQS queue.

```hcl
  statement {
    sid = "Allow SNS"
    effect  = "Allow"
    actions = ["kms:GenerateDataKey*", "kms:Decrypt"]
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    resources = ["*"]
  }
```

### Integrating encrypted SQS and encrypted Lambda

- Create an event source mapping

```hcl
resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn = aws_sqs_queue.terraform_queue.arn
  function_name    = aws_lambda_function.test_lambda.arn
}
```

- Allow Lambda IAM Role to receive SQS messages. 
```
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
```

- Allow Lambda IAM Role to Decrypt the message

```
  statement {
    sid    = "AllowKMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = [aws_kms_key.sqs.arn]
  }
```

- SQS Access Policy DO NOT need to allow Lambda to `sqs:ReceiveMessage` and `sqs:DeleteMessage` (why?)

- In the SQS KMS key policy, DO NOT use principal `Service` with `lambda.amazonaws.com` to allow Lambda access to decrypt messages. Use the Lambda IAM Role instead.

```
"aws_iam_policy_document" "kms_sqs" {
     effect  = "Allow"
     actions = ["kms:Decrypt"]
     principals {
-      type        = "Service"
-      identifiers = ["lambda.amazonaws.com"]
+      type        = "AWS"
+      identifiers = [aws_iam_role.iam_for_lambda.arn]
     }
     resources = ["*"]
   }
```

## Troubleshooting errors

Just by using the console and checking CloudWatch logs sometimes is not straightforward to understand what is happening behind the scenes.

If the integration is not working between components, it is useful to enable a trail in CloudTrail to check for permission problems. 

This is an example of what CloudTrail can tell you:

```
{
    "eventVersion": "1.05",
    "userIdentity": {
        "type": "AssumedRole",
        "principalId": "AROA4OI5V3FH32TUB3Z3K:awslambda_701_20201111224653900",
        "arn": "arn:aws:sts::855297612111:assumed-role/iam_for_lambda/awslambda_701_20201111224653900",
        "accountId": "855297612111",
        "accessKeyId": "ASIAIFFOHKY26SPS3IFA",
        "sessionContext": {
            "sessionIssuer": {
                "type": "Role",
                "principalId": "AROA4OI5V3FH32TUB3Z3K",
                "arn": "arn:aws:iam::855297612111:role/iam_for_lambda",
                "accountId": "855297612111",
                "userName": "iam_for_lambda"
            },
            ...
        },
        "invokedBy": "sqs.amazonaws.com"
    },
    ...
    "eventSource": "kms.amazonaws.com",
    "eventName": "Decrypt",
    "awsRegion": "ap-southeast-2",
    "sourceIPAddress": "sqs.amazonaws.com",
    "userAgent": "sqs.amazonaws.com",
    "errorCode": "AccessDenied",
    "errorMessage": "User: arn:aws:sts::855297612111:assumed-role/iam_for_lambda/awslambda_701_20201111224653900 is not authorized to perform: kms:Decrypt on resource: arn:aws:kms:ap-southeast-2:855297612111:key/9a58b574-8756-4f7f-aa64-b9234b307bfe",
    ...
}
```

Here the `errorMessage` is your best friend. It tells you which `identity` (user, role, group) tried to perform which `action` on which `resource`. 
In this example it is clear I forgot to grant access `kms:Decrypt` for the SQS KMS key to the Lambda IAM Role.
