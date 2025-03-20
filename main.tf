provider "aws" {
  region = "us-east-1"
}

# S3 Bucket for SFTP
resource "aws_s3_bucket" "cap_sftp" {
  bucket = "cap-sftp-bucket-saul"
}

# IAM Role for SFTP Server
resource "aws_iam_role" "sftp_role" {
  name = "cap-sftp-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "transfer.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "sftp_s3_access" {
  role       = aws_iam_role.sftp_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

# SFTP Server
resource "aws_transfer_server" "sftp" {
  identity_provider_type = "SERVICE_MANAGED"
  endpoint_type          = "PUBLIC"
  protocols              = ["SFTP"]
  logging_role           = aws_iam_role.sftp_role.arn
}

# SFTP User
resource "aws_transfer_user" "sftp_user" {
  server_id           = aws_transfer_server.sftp.id
  user_name           = "sftpuser"
  role                = aws_iam_role.sftp_role.arn
  home_directory_type = "PATH"
  home_directory      = "/${aws_s3_bucket.cap_sftp.bucket}/uploads"
}

# SSH Public Key for SFTP User
resource "aws_transfer_ssh_key" "sftp_user_key" {
  server_id  = aws_transfer_server.sftp.id
  user_name  = aws_transfer_user.sftp_user.user_name
  body       = file("cap-sftp-key-legacy.pub")  # Ensure this file is in ~/abel_takehome
}

# Store Private Key in AWS Secrets Manager
resource "aws_secretsmanager_secret" "sftp_private_key" {
  name        = "cap-sftp-private-key"
  description = "Private key for SFTP user sftpuser"
}

resource "aws_secretsmanager_secret_version" "sftp_private_key_version" {
  secret_id     = aws_secretsmanager_secret.sftp_private_key.id
  secret_string = file("cap-sftp-key-legacy.txt")  # Ensure this file is in ~/abel_takehome
}

# Output SFTP Endpoint
output "sftp_endpoint" {
  value = aws_transfer_server.sftp.endpoint
}