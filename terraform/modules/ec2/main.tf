resource "aws_instance" "app_server" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  iam_instance_profile   = var.iam_instance_profile
  key_name               = var.key_name
  user_data              = var.user_data

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name        = "${var.project_name}-app-server"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_eip" "app_server" {
  domain   = "vpc"
  instance = aws_instance.app_server.id

  tags = {
    Name        = "${var.project_name}-app-eip"
    Environment = var.environment
  }
}
