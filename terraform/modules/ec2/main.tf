# آخرین نسخه Amazon Linux 2023 رو پیدا میکنه
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_iam_role" "ec2_role" {
  name = "proj2-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{ Action = "sts:AssumeRole", Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" } }]
  })
}

resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "profile" {
  name = "proj2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro" # free tier
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [var.sg_id]
  key_name               = "ansible"
  iam_instance_profile   = aws_iam_instance_profile.profile.name

  tags = { Name = "proj2-app-server" }
}

variable "vpc_id" { type = string }
variable "subnet_id" { type = string }
variable "sg_id" { type = string }

output "instance_id" { value = aws_instance.app.id }
output "public_ip" { value = aws_instance.app.public_ip }