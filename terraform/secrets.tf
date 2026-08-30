resource "random_password" "postgres_password" {
  length  = 12
  special = false
}

resource "aws_secretsmanager_secret" "postgres" {
  name = "devboard/postgres"
}

resource "aws_secretsmanager_secret_version" "postgresql" {
  secret_id = aws_secretsmanager_secret.postgres.id
  secret_string = jsonencode({
    engine   = "postgres"
    port     = 5432
    username = "devboard"
    password = random_password.postgres_password.result
    dbname   = "devboard"
  })

  lifecycle {
    ignore_changes = [secret_string]
  }
}