terraform {
  required_version = ">= 0.13"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 2.89.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 2.1.0"
    }
    postgresql = {
      source  = "cyrilgdn/postgresql"
      version = "~> 1.14.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1.0"
    }
  }
}

provider "azurerm" {
  features {}
}

locals {
  databases_map = { for db in var.databases : db.name => db }

  users_flatten = flatten([for db in var.databases :
    [for user in db.users : {
      db : db
      user : user
  }]])
  users_map = { for user in local.users_flatten : user.user.name => user }

  grants = flatten([for db in var.databases : [for user in db.users : [for grant in user.grants : {
    database : db.name
    username : user.name
    object_type : grant.object_type
    privileges : grant.privileges
  }]]])

  tier_names = {
    "Basic" : "B",
    "GeneralPurpose" : "GP",
    "MemoryOptimized" : "MO",
  }

  sku_name = "${local.tier_names[var.sku.tier]}_${var.sku.family}_${var.sku.capacity}"

  firewall_rules = [for rule in var.network_rules.ip_rules : {
    start : cidrhost(rule, 0)
    end : cidrhost(rule, pow(2, (32 - parseint(split("/", rule)[1], 10))) - 1)
  }]

  geo_redundant_backup_enabled = var.geo_redundant_backup == "Enabled" ? true : false
  auto_grow_enabled            = var.storage_auto_grow == "Enabled" ? true : false

  diag_resource_list = var.diagnostics != null ? split("/", var.diagnostics.destination) : []
  parsed_diag = var.diagnostics != null ? {
    log_analytics_id   = contains(local.diag_resource_list, "Microsoft.OperationalInsights") ? var.diagnostics.destination : null
    storage_account_id = contains(local.diag_resource_list, "Microsoft.Storage") ? var.diagnostics.destination : null
    event_hub_auth_id  = contains(local.diag_resource_list, "Microsoft.EventHub") ? var.diagnostics.destination : null
    metric             = var.diagnostics.metrics
    log                = var.diagnostics.logs
    } : {
    log_analytics_id   = null
    storage_account_id = null
    event_hub_auth_id  = null
    metric             = []
    log                = []
  }
}

data "http" "myip" {
  url = "http://ipv4.icanhazip.com"
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

  sku_name = local.sku_name

  storage_mb                   = var.storage_mb
  backup_retention_days        = var.backup_retention_days
  geo_redundant_backup_enabled = local.geo_redundant_backup_enabled
  auto_grow_enabled            = local.auto_grow_enabled

  administrator_login          = var.administrator
  administrator_login_password = var.administrator_password != null ? var.administrator_password : random_string.unique.result
  version                      = var.server_version
  ssl_enforcement_enabled      = true

  tags = var.tags

  lifecycle {
    ignore_changes = [threat_detection_policy]
  }
}

data "azurerm_monitor_diagnostic_categories" "default" {
  resource_id = azurerm_postgresql_server.main.id
}

resource "azurerm_monitor_diagnostic_setting" "namespace" {
  count                          = var.diagnostics != null ? 1 : 0
  name                           = "${var.name}-pgsql-diag"
  target_resource_id             = azurerm_postgresql_server.main.id
  log_analytics_workspace_id     = local.parsed_diag.log_analytics_id
  eventhub_authorization_rule_id = local.parsed_diag.event_hub_auth_id
  eventhub_name                  = local.parsed_diag.event_hub_auth_id != null ? var.diagnostics.eventhub_name : null
  storage_account_id             = local.parsed_diag.storage_account_id

  # For each available log category, check if it should be enabled and set enabled = true if it should.
  # All other categories are created with enabled = false to prevent TF from showing changes happening with each plan/apply.
  # Ref: https://github.com/terraform-providers/terraform-provider-azurerm/issues/7235
  dynamic "log" {
    for_each = data.azurerm_monitor_diagnostic_categories.default.logs
    content {
      category = log.value
      enabled  = contains(local.parsed_diag.log, "all") || contains(local.parsed_diag.log, log.value)

      retention_policy {
        enabled = false
        days    = 0
      }
    }
  }

  # For each available metric category, check if it should be enabled and set enabled = true if it should.
  # All other categories are created with enabled = false to prevent TF from showing changes happening with each plan/apply.
  # Ref: https://github.com/terraform-providers/terraform-provider-azurerm/issues/7235
  dynamic "metric" {
    for_each = data.azurerm_monitor_diagnostic_categories.default.metrics
    content {
      category = metric.value
      enabled  = contains(local.parsed_diag.metric, "all") || contains(local.parsed_diag.metric, metric.value)

      retention_policy {
        enabled = false
        days    = 0
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
  count = length(local.firewall_rules)

  name                = "netrule_${count.index}"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_postgresql_server.main.name
  start_ip_address    = local.firewall_rules[count.index].start
  end_ip_address      = local.firewall_rules[count.index].end
}

resource "azurerm_postgresql_firewall_rule" "azure" {
  count = var.network_rules.allow_access_to_azure_services ? 1 : 0

  name                = "allow_azure_access"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_postgresql_server.main.name
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}

resource "azurerm_postgresql_firewall_rule" "client" {
  count = var.network_rules.allow_access_to_azure_services ? 1 : 0

  name                = "terraform_client"
  resource_group_name = azurerm_resource_group.main.name
  server_name         = azurerm_postgresql_server.main.name
  start_ip_address    = chomp(data.http.myip.body)
  end_ip_address      = chomp(data.http.myip.body)
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
  max_connections = 1
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
  password        = each.value.user.password != null ? each.value.user.password : random_string.user[each.key].result

  depends_on = [
    azurerm_postgresql_firewall_rule.client
  ]
}

resource "postgresql_grant" "user_privileges" {
  count = length(local.grants)

  database    = azurerm_postgresql_database.main[local.grants[count.index].database].name
  schema      = "public"
  role        = postgresql_role.user[local.grants[count.index].username].name
  object_type = local.grants[count.index].object_type
  privileges  = local.grants[count.index].privileges

  depends_on = [
    azurerm_postgresql_firewall_rule.client
  ]
}
