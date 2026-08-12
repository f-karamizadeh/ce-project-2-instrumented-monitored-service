provider "aws" {
  region = "us-east-1"
}

module "network" {
  source = "./modules/network"
}

module "ec2" {
  source    = "./modules/ec2"
  vpc_id    = module.network.vpc_id
  subnet_id = module.network.public_subnet_id
  sg_id     = module.network.sg_id
}

module "monitoring" {
  source      = "./modules/monitoring"
  alert_email = "f.karamizadeh@gmail.com"
}