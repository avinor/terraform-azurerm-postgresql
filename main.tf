terraform {
  required_version = ">= 0.12.0"
  required_providers {
    azurerm    = "~> 1.35.0"
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}