terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16.0"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}
