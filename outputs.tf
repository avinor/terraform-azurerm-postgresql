output "id" {
  description = "The ID of the PostgreSQL Server."
  value       = azurerm_postgresql_server.main.id
}

output "fqdn" {
  description = "The fqdn of the PostgreSQL Server."
  value       = azurerm_postgresql_server.main.fqdn
}

output "adminpassword" {
  description = "Admin password for the server."
  value       = random_password.unique.result
  sensitive   = true
}

output "users" {
  description = "List of users created and their passwords."
  value       = { for user in postgresql_role.user : user.name => user.password }
  sensitive   = true
}