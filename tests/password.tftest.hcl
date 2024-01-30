variables {
  name                = "password"
  resource_group_name = "password-postgresql-rg"
  location            = "westeurope"

  sku = {
    capacity = 1
    tier     = "Basic"
    family   = "Gen5"
  }

  geo_redundant_backup   = "Enabled"
  storage_auto_grow      = "Disabled"
  administrator_password = "secretpassword"

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
        {
          name     = "a_user2"
          password = "secretpassword"
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

run "simple" {
  command = plan
}