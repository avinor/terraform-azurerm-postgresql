terraform {
  required_version = ">= 0.12.6"
  required_providers {
    azurerm = "~> 1.36.0"
  }
}

locals {
  databases_map = { for db in var.databases : db.name => db }

  users_flatten = flatten([for db in var.databases :
    [for user in db.users : {
      db : db
      user : user
  }]])
  users_map = { for user in local.users_flatten : user.user.name => user }

  diag_pgsql_logs = [
    "PostgreSQLLogs",
    "QueryStoreRuntimeStatistics",
    "QueryStoreWaitStatistics",
  ]
  diag_pgsql_metrics = [
    "AllMetrics",
  ]

  diag_resource_list = var.diagnostics != null ? split("/", var.diagnostics.destination) : []
  parsed_diag = var.diagnostics != null ? {
    log_analytics_id   = contains(local.diag_resource_list, "microsoft.operationalinsights") ? var.diagnostics.destination : null
    storage_account_id = contains(local.diag_resource_list, "Microsoft.Storage") ? var.diagnostics.destination : null
    event_hub_auth_id  = contains(local.diag_resource_list, "Microsoft.EventHub") ? var.diagnostics.destination : null
    metric             = contains(var.diagnostics.metrics, "all") ? local.diag_pgsql_metrics : var.diagnostics.metrics
    log                = contains(var.diagnostics.logs, "all") ? local.diag_pgsql_logs : var.diagnostics.logs
    } : {
    log_analytics_id   = null
    storage_account_id = null
    event_hub_auth_id  = null
    metric             = []
    log                = []
  }
}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location

  tags = var.tags
}

resource "random_string" "unique" {
  length  = 16
  special = true
  upper   = true
}

resource "azurerm_postgresql_server" "main" {
  name                = "${var.name}-pgsql"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  sku {
    name     = var.sku.name
    capacity = var.sku.capacity
    tier     = var.sku.tier
    family   = var.sku.family
  }

  storage_profile {
    storage_mb            = var.storage_mb
    backup_retention_days = var.backup_retention_days
    geo_redundant_backup  = var.geo_redundant_backup
    auto_grow             = var.storage_auto_grow
  }

  administrator_login          = var.administrator
  administrator_login_password = random_string.unique.result
  version                      = var.server_version
  ssl_enforcement              = "Enabled"

  tags = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "namespace" {
  count                          = var.diagnostics != null ? 1 : 0
  name                           = "${var.name}-pgsql-diag"
  target_resource_id             = azurerm_postgresql_server.main.id
  log_analytics_workspace_id     = local.parsed_diag.log_analytics_id
  eventhub_authorization_rule_id = local.parsed_diag.event_hub_auth_id
  eventhub_name                  = local.parsed_diag.event_hub_auth_id != null ? var.diagnostics.eventhub_name : null
  storage_account_id             = local.parsed_diag.storage_account_id

  dynamic "log" {
    for_each = local.parsed_diag.log
    content {
      category = log.value

      retention_policy {
        enabled = false
      }
    }
  }

  dynamic "metric" {
    for_each = local.parsed_diag.metric
    content {
      category = metric.value

      retention_policy {
        enabled = false
      }
    }
  }
}

resource "azurerm_postgresql_configuration" "main" {
  for_each = var.configuration

  name                = each.key
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_postgresql_server.main.name
  value               = each.value
}

resource "azurerm_postgresql_firewall_rule" "main" {
  count = length(var.network_rules.ip_rules)

  name                = "netrule_${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_postgresql_server.main.name
  start_ip_address    = cidrhost(var.network_rules.ip_rules[count.index], 0)
  end_ip_address      = cidrhost(var.network_rules.ip_rules[count.index], 1)
}

resource "azurerm_postgresql_firewall_rule" "azure" {
  count = var.network_rules.allow_access_to_azure_services ? 1 : 0

  name                = "allow_azure_access"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_postgresql_server.main.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

resource "azurerm_postgresql_virtual_network_rule" "main" {
  count = length(var.network_rules.subnet_ids)

  name                                 = "postgresql-vnet-rule"
  resource_group_name                  = azurerm_resource_group.main.name
  server_name                          = azurerm_postgresql_server.main.name
  subnet_id                            = var.network_rules.subnet_ids[count.index]
  ignore_missing_vnet_service_endpoint = true
}

resource "azurerm_postgresql_database" "main" {
  for_each = local.databases_map

  name                = each.key
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_postgresql_server.main.name
  charset             = each.value.charset
  collation           = each.value.collation
}

provider "postgresql" {
  host             = azurerm_postgresql_server.main.fqdn
  port             = 5432
  username         = "${var.administrator}@${azurerm_postgresql_server.main.name}"
  password         = random_string.unique.result
  sslmode          = "require"
  superuser        = false
  connect_timeout  = 15
  expected_version = var.server_version
}

resource "random_string" "user" {
  for_each = local.users_map

  length  = 16
  special = true
  upper   = true
}

resource "postgresql_role" "user" {
  for_each = local.users_map

  name            = each.key
  login           = true
  superuser       = false
  create_database = false
  create_role     = false
  inherit         = true
  replication     = false
  password        = random_string.user[each.key].result
}

# resource postgresql_grant "user" {
#   for_each = local.users_map

#   database    = each.value.db.name
#   role        = postgresql_role.user[each.key].name
#   schema      = "public"
#   object_type = "table"
#   privileges  = each.value.user.privileges
# }