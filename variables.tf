variable "name" {
  description = "Name of the PostgreSQL server."
}

variable "resource_group_name" {
  description = "Name of resource group to deploy resources in."
}

variable "location" {
  description = "The Azure Region in which to create resource."
}

variable "sku" {
  description = "SKU settings of server, see https://www.terraform.io/docs/providers/azurerm/r/postgresql_server.html for details."
  type        = object({ capacity = number, tier = string, family = string })
}

variable "storage_mb" {
  description = "Max storage allowed for server."
  type        = number
  default     = 5120
}

variable "backup_retention_days" {
  description = "Backup retention days for the server."
  type        = number
  default     = 7
}

variable "geo_redundant_backup" {
  description = "Enable / Disable geo-redundant for server backup."
  default     = "Disabled"
}

variable "storage_auto_grow" {
  description = "Enable / Disable auto growing of storage."
  default     = "Enabled"
}

variable "administrator" {
  description = "Name of administrator user, password is auto generated."
  default     = "pgsqladmin"
}

variable "server_version" {
  description = "PostgreSql version to use on server."
  default     = "11"
}

variable "configuration" {
  description = "Map with PostgreSQL configurations."
  type        = map(string)
  default     = {}
}

variable "diagnostics" {
  description = "Diagnostic settings for those resources that support it. See README.md for details on configuration."
  type        = object({ destination = string, eventhub_name = string, logs = list(string), metrics = list(string) })
  default     = null
}

variable "network_rules" {
  description = "Network rules restricing access to the postgresql server."
  type        = object({ ip_rules = list(string), subnet_ids = list(string), allow_access_to_azure_services = bool })
  default = {
    ip_rules                       = []
    subnet_ids                     = []
    allow_access_to_azure_services = true
  }
}

variable "databases" {
  description = "List of databases and users with access to them. Assigning users require that the provisioner have access to database."
  type = list(object({
    name      = string,
    charset   = string,
    collation = string,
    users = list(object({
      name       = string,
      privileges = list(string)
    }))
  }))
  default = []
}

variable "tags" {
  description = "Tags to apply to all resources created."
  type        = map(string)
  default     = {}
}