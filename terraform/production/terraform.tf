terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.82.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.16.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.55"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}
