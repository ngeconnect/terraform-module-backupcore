# Data source générique
data "azurerm_client_config" "current" {}

# 0. Prérequis : RG de backup (si tu veux un RG dédié)
resource "azurerm_resource_group" "backup_core_rg" {
  name     = var.backup_core_rg_name
  location = var.db_backup_region
}

# 1. Backup Vault (UN SEUL pour tous les env)
resource "azurerm_data_protection_backup_vault" "cluster_backup_vault" {
  name                = "backup-vault-${var.clustername}"   # ou nom fixe
  resource_group_name = var.backup_core_rg_name                  # ou backup_rg.name si tu veux
  location            = var.db_backup_region
  datastore_type      = "OperationalStore"
  redundancy          = "LocallyRedundant"

  identity {
    type = "SystemAssigned"
  }
  lifecycle {
    ignore_changes  = [tags]
    prevent_destroy = true
  }
}

# 5. Policy de backup (UNE policy partagée)
resource "azurerm_data_protection_backup_policy_kubernetes_cluster" "mongodb_policy" {
  name                = "db-backup-policy"
  resource_group_name = var.backup_core_rg_name
  vault_name          = azurerm_data_protection_backup_vault.cluster_backup_vault.name

  backup_repeating_time_intervals = var.backup_repeating_time_intervals

  default_retention_rule {
    life_cycle {
      duration        = "P${var.db_bkp_max_count}D"
      data_store_type = "OperationalStore"
    }
  }
}

# 2. Storage Account + 3. Container (si tu veux un SEUL compte mutualisé)
resource "azurerm_storage_account" "backup_sa" {
  name                    = "aksbackup${var.environment}rsmartvault"
  resource_group_name     = var.backup_core_rg_name
  location                = var.db_backup_region
  account_tier            = "Standard"
  account_replication_type = "LRS"

  depends_on = [azurerm_resource_group.backup_core_rg]
}

resource "azurerm_storage_container" "backup_container" {
  name                  = "aksbackup"
  storage_account_id    = azurerm_storage_account.backup_sa.id
  container_access_type = "private"

  depends_on = [azurerm_storage_account.backup_sa]
}

# Outputs pour que les modules env les consomment
output "backup_vault_id" {
  value = azurerm_data_protection_backup_vault.cluster_backup_vault.id
}

output "backup_vault_name" {
  value = azurerm_data_protection_backup_vault.cluster_backup_vault.name
}

output "backup_policy_id" {
  value = azurerm_data_protection_backup_policy_kubernetes_cluster.mongodb_policy.id
}

output "backup_db_bkp_rg" {
  value = azurerm_resource_group.backup_core_rg.name
}

output "backup_sa_name" {
  value = azurerm_storage_account.backup_sa.name
}

output "backup_container_name" {
  value = azurerm_storage_container.backup_container.name
}