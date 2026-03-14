provider "aws" {
  region = var.region
}

# --- DynamoDB ---
resource "aws_dynamodb_table" "greet_logs" {
  name         = "GreetingLogs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"
  attribute {
    name = "id"
    type = "S"
  }
}

# --- IAM Role for Lambda ---
resource "aws_iam_role" "lambda_role" {
  name = "lambda-role-${var.region}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  role = aws_iam_role.lambda_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = aws_dynamodb_table.greet_logs.arn
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ecs:RunTask", "iam:PassRole"]
        Resource = "*"
      }
    ]
  })
}

# --- Lambda 1: Greeter ---
data "archive_file" "greeter_zip" {
  type        = "zip"
  output_path = "${path.module}/greeter.zip"
  source {
    content  = <<EOF
import boto3, json, uuid, os

def handler(event, context):
    region = os.environ['AWS_REGION']
    dynamo = boto3.client('dynamodb', region_name=region)
    dynamo.put_item(
        TableName='GreetingLogs',
        Item={'id': {'S': str(uuid.uuid4())}, 'region': {'S': region}}
    )
    sns = boto3.client('sns', region_name='us-east-1')
    sns.publish(
        TopicArn='arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic',
        Message=json.dumps({
            "email": "${var.your_email}",
            "source": "Lambda",
            "region": region,
            "repo": "${var.github_repo}"
        })
    )
    return {'statusCode': 200, 'body': json.dumps({'region': region})}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "greeter" {
  filename         = data.archive_file.greeter_zip.output_path
  function_name    = "greeter-${var.region}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.greeter_zip.output_base64sha256
}

# --- Lambda 2: Dispatcher ---
data "archive_file" "dispatcher_zip" {
  type        = "zip"
  output_path = "${path.module}/dispatcher.zip"
  source {
    content  = <<EOF
import boto3, os, json

def handler(event, context):
    region = os.environ['AWS_REGION']
    ecs = boto3.client('ecs', region_name=region)
    ecs.run_task(
        cluster=os.environ['ECS_CLUSTER'],
        taskDefinition=os.environ['TASK_DEF'],
        launchType='FARGATE',
        networkConfiguration={
            'awsvpcConfiguration': {
                'subnets': [os.environ['SUBNET_ID']],
                'assignPublicIp': 'ENABLED'
            }
        }
    )
    return {'statusCode': 200, 'body': json.dumps({'region': region, 'status': 'task launched'})}
EOF
    filename = "index.py"
  }
}

resource "aws_lambda_function" "dispatcher" {
  filename         = data.archive_file.dispatcher_zip.output_path
  function_name    = "dispatcher-${var.region}"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = data.archive_file.dispatcher_zip.output_base64sha256
  environment {
    variables = {
      ECS_CLUSTER = aws_ecs_cluster.main.name
      TASK_DEF    = aws_ecs_task_definition.sns_publisher.arn
      SUBNET_ID   = aws_subnet.public.id
    }
  }
}

# --- VPC (public subnet, no NAT to save cost) ---
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}a"
}
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- ECS Cluster ---
resource "aws_ecs_cluster" "main" {
  name = "unleash-cluster-${var.region}"
}

# --- IAM Role for ECS Task ---
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role-${var.region}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy" "ecs_task_policy" {
  role = aws_iam_role.ecs_task_role.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic"
    }]
  })
}
resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-exec-role-${var.region}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "ecs_exec_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- ECS Task Definition ---
resource "aws_ecs_task_definition" "sns_publisher" {
  family                   = "sns-publisher-${var.region}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  container_definitions = jsonencode([{
    name  = "sns-publisher"
    image = "amazon/aws-cli"
    command = [
      "sns", "publish",
      "--region", "us-east-1",
      "--topic-arn", "arn:aws:sns:us-east-1:637226132752:Candidate-Verification-Topic",
      "--message", "{\"email\":\"${var.your_email}\",\"source\":\"ECS\",\"region\":\"${var.region}\",\"repo\":\"${var.github_repo}\"}"
    ]
    essential = true
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/sns-publisher-${var.region}"
        awslogs-region        = var.region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/sns-publisher-${var.region}"
  retention_in_days = 1
}

# --- API Gateway ---
resource "aws_apigatewayv2_api" "main" {
  name          = "unleash-api-${var.region}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  authorizer_type  = "JWT"
  name             = "cognito-authorizer"
  identity_sources = ["$request.header.Authorization"]
  jwt_configuration {
    audience = [var.cognito_user_pool_client_id]
    issuer   = "https://cognito-idp.us-east-1.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# Lambda permissions + integrations + routes for /greet and /dispatch
resource "aws_lambda_permission" "greeter" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
resource "aws_lambda_permission" "dispatcher" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "greeter" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.invoke_arn
  payload_format_version = "2.0"
}
resource "aws_apigatewayv2_integration" "dispatcher" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "greet" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /greet"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.greeter.id}"
}
resource "aws_apigatewayv2_route" "dispatch" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /dispatch"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
  target             = "integrations/${aws_apigatewayv2_integration.dispatcher.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}
