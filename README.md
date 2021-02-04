# PostgresSQL server

Terraform module to create a PostgreSQL server in Azure with set of databases and users. Database allows for custom configuration and enforces SSL for security reasons.

## Limitations

Due to some limitations in terraform it does not handle the postgresql provider correctly. It will fail on first deployment due to server host does not exist. Only way to fix that now is to comment out the postgresql provider, postgresql resources and postgresql output. Then run first time to create server and comment in other resources and run again.

## Usage

Example showing deployment of a server with single database using [tau](https://github.com/avinor/tau)

```terraform
module {
  source  = "avinor/postgresql/azurerm"
  version = "1.0.0"
}

inputs {
  name                = "simple"
  resource_group_name = "simple-postgresql-rg"
  location            = "westeurope"

  sku = {
    name     = "B_Gen5_1"
    capacity = 1
    tier     = "Basic"
    family   = "Gen5"
  }

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
```

## Diagnostics

Diagnostics settings can be sent to either storage account, event hub or Log Analytics workspace. The variable `diagnostics.destination` is the id of receiver, ie. storage account id, event namespace authorization rule id or log analytics resource id. Depending on what id is it will detect where to send. Unless using event namespace the `eventhub_name` is not required, just set to `null` for storage account and log analytics workspace.

Setting `all` in logs and metrics will send all possible diagnostics to destination. If not using `all` type name of categories to send.

## Grant access

Each user can be given a set of user grants. Each grant consists of an `object_type` and a list of `privileges`.
`object_type` can be one of: `database`, `table`, `sequence` and `function`.
`privileges` can be one or more of: `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `TRUNCATE`, `REFERENCES`, `TRIGGER`, `CREATE`, `CONNECT`, `TEMPORARY`, `EXECUTE`, and `USAGE`

Example:

Create a user that can create a table, select from and update it.
To be able to create a table it needs the `CREATE` privilege on the `database` object:
```
{
  object_type : "database"
  privileges : ["CREATE"]
}
```
Note: This does not mean the user is allowed to create a new database.

To be able to select from and update the table, we can give it `SELECT`, `UPDATE` and `INSERT` privileges on the `table` object:
```
{
  object_type : "table"
  privileges : ["SELECT", "INSERT", "UPDATE"]
}
```

For more details on privileges in PostgreSQL see the official documentation: <https://www.postgresql.org/docs/13/ddl-priv.html>
