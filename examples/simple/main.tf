module "simple" {
  source = "../.."

  name                = "simple"
  resource_group_name = "simple-postgresql-rg"
  location            = "westeurope"

  sku = {
    name     = "B_Gen5_1"
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
          name = "a_user"
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
}