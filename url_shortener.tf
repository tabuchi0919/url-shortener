resource "aws_s3_bucket" "url-shortener" {
  acl           = "private"
  bucket        = "your-url-shortener"
  force_destroy = false
  website {
    index_document = "index.html"
  }
}

resource "aws_iam_role" "url-shortener-lambda" {
  name = "url-shortener-lambda"
  assume_role_policy = jsonencode(
    {
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Principal = {
            Service = "lambda.amazonaws.com"
          }
        },
      ]
      Version = "2012-10-17"
    }
  )
}

resource "aws_iam_policy" "access-s3-url-shortener" {
  name = "access-s3-url-shortener"
  policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Sid" : "VisualEditor0",
          "Effect" : "Allow",
          "Action" : "s3:*",
          "Resource" : "${aws_s3_bucket.url-shortener.arn}/*"
        },
        {
          "Sid" : "VisualEditor1",
          "Effect" : "Allow",
          "Action" : "s3:ListBucket",
          "Resource" : aws_s3_bucket.url-shortener.arn
        }
      ]
    }
  )
}

data "aws_iam_policy" "AWSLambdaBasicExecutionRole" {
  arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "url-shortener-lambda-1" {
  role       = aws_iam_role.url-shortener-lambda.name
  policy_arn = aws_iam_policy.access-s3-url-shortener.arn
}

resource "aws_iam_role_policy_attachment" "url-shortener-lambda-2" {
  role       = aws_iam_role.url-shortener-lambda.name
  policy_arn = data.aws_iam_policy.AWSLambdaBasicExecutionRole.arn
}

resource "aws_cloudwatch_log_group" "url-shortener" {
  name = "/aws/lambda/${aws_lambda_function.url-shortener.function_name}"
}

data "archive_file" "url_shortener" {
  type        = "zip"
  source_dir  = "url_shortener"
  output_path = "output/url_shortener.zip"
}

resource "aws_lambda_function" "url-shortener" {
  filename         = data.archive_file.url_shortener.output_path
  source_code_hash = data.archive_file.url_shortener.output_base64sha256
  function_name    = "url-shortener"
  handler          = "index.handler"
  role             = aws_iam_role.url-shortener-lambda.arn
  runtime          = "ruby2.7"
  memory_size      = "128"
}

resource "aws_api_gateway_rest_api" "url-shortener" {
  name = "buchi-url-shortener"
}

resource "aws_api_gateway_resource" "generate" {
  rest_api_id = aws_api_gateway_rest_api.url-shortener.id
  parent_id   = aws_api_gateway_rest_api.url-shortener.root_resource_id
  path_part   = "generate"
}

resource "aws_api_gateway_method" "generate" {
  rest_api_id   = aws_api_gateway_rest_api.url-shortener.id
  resource_id   = aws_api_gateway_resource.generate.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "generate" {
  rest_api_id             = aws_api_gateway_rest_api.url-shortener.id
  resource_id             = aws_api_gateway_method.generate.resource_id
  http_method             = aws_api_gateway_method.generate.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = aws_lambda_function.url-shortener.invoke_arn
}

resource "aws_api_gateway_deployment" "prod" {
  depends_on  = [aws_api_gateway_integration.generate]
  rest_api_id = aws_api_gateway_rest_api.url-shortener.id
  stage_name  = "prod"
}

resource "aws_route53_zone" "your-domain" {
  name    = "your-domain"
  comment = ""
}

resource "aws_acm_certificate" "your-domain" {
  provider    = aws.ue1
  domain_name = "your-domain"
}

resource "aws_route53_record" "url-shortener-acm" {
  zone_id = aws_route53_zone.your-domain.zone_id
  name    = tolist(aws_acm_certificate.your-domain.domain_validation_options)[0].resource_record_name
  type    = tolist(aws_acm_certificate.your-domain.domain_validation_options)[0].resource_record_type
  ttl     = 300
  records = [tolist(aws_acm_certificate.your-domain.domain_validation_options)[0].resource_record_value]
}

resource "aws_route53_record" "url-shortener" {
  zone_id = aws_route53_zone.your-domain.zone_id
  name    = "your-domain"
  type    = "A"
  alias {
    evaluate_target_health = false
    name                   = aws_cloudfront_distribution.url-shortener.domain_name
    zone_id                = aws_cloudfront_distribution.url-shortener.hosted_zone_id
  }
}

resource "aws_cloudfront_distribution" "url-shortener" {
  aliases = [
    "your-domain",
  ]
  enabled         = true
  is_ipv6_enabled = true
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-website-url-shortener"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
  }
  ordered_cache_behavior {
    allowed_methods = [
      "DELETE",
      "GET",
      "HEAD",
      "OPTIONS",
      "PATCH",
      "POST",
      "PUT",
    ]
    cached_methods         = ["GET", "HEAD"]
    path_pattern           = "/generate"
    target_origin_id       = "api-gateway-url-shortener"
    viewer_protocol_policy = "redirect-to-https"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }
  origin {
    domain_name = aws_s3_bucket.url-shortener.website_endpoint
    origin_id   = "s3-website-url-shortener"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
      ]
    }
  }
  origin {
    domain_name = "${aws_api_gateway_rest_api.url-shortener.id}.execute-api.ap-northeast-1.amazonaws.com"
    origin_path = "/prod"
    origin_id   = "api-gateway-url-shortener"
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2",
      ]
    }
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.your-domain.arn
    minimum_protocol_version = "TLSv1.2_2019"
    ssl_support_method       = "sni-only"
  }
}
