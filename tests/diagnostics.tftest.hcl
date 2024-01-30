variables {
  name                = "simple"
  resource_group_name = "simple-postgresql-rg"
  location            = "westeurope"

  sku = {
    capacity = 1
    tier     = "Basic"
    family   = "Gen5"
  }

  geo_redundant_backup = "Enabled"
  storage_auto_grow    = "Disabled"

  databases = [
    {
      name      = "my_database"
      charset   = "UTF8"
      collation = "English_United States.1252"
      users = [
        {
          name     = "a_user"
          password = null
          grants = [
            {
              object_type : "database"
              privileges : ["CREATE"]
            },
            {
              object_type : "table"
              privileges : ["SELECT", "INSERT", "UPDATE"]
            }
          ]
        },
      ]
    },
  ]

  diagnostics = {
    destination   = "/subscriptions/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx/resourceGroups/my-rg/providers/Microsoft.OperationalInsights/workspaces/my-log-analytics"
    eventhub_name = null
    logs          = ["PostgreSQLLogs"]
    metrics       = ["all"]
  }
}

run "simple" {
  command = plan
}