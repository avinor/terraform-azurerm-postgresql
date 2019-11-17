# PostgresSQL server

Terraform module to create a PostgreSQL server in Azure with set of databases and users. Database allows for custom configuration and enforces SSL for security reasons.

Currently it has some limitations with granting access for users as the PostgreSQL terraform provider does not support granting other privileges than table and sequence in databases. This will be resolved once provider supports this. In the meantime to grant access to databases the administrator needs to connect to database after provisioning and grant correct privileges. Module will create all databases and users, just need to grant privileges.

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
        name      = "something"
        charset   = "UTF8"
        collation = "English_United States.1252"
        users = [
            {
                name = "something"
                privileges = ["ALL PRIVILEGES"]
            }
        ]
        }
    ]
}
```

## Diagnostics

Diagnostics settings can be sent to either storage account, event hub or Log Analytics workspace. The variable `diagnostics.destination` is the id of receiver, ie. storage account id, event namespace authorization rule id or log analytics resource id. Depending on what id is it will detect where to send. Unless using event namespace the `eventhub_name` is not required, just set to `null` for storage account and log analytics workspace.

Setting `all` in logs and metrics will send all possible diagnostics to destination. If not using `all` type name of categories to send.

## Grant access

After deployment it have created the server, databases and users (roles), but not granted access. To change the owner of database logon with administrator and run following command to change owner on database called `something`:

1. `GRANT something TO <adminuser>;`
2. `ALTER DATABASE <database> OWNER TO something;`

## References

- <https://docs.microsoft.com/en-us/azure/postgresql/howto-create-users>
