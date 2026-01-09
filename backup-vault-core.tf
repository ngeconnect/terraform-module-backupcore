# Data source générique
data "azurerm_client_config" "current" {}

# Le cluster AKS (besoin pour son identité et l'extension)
data "azurerm_kubernetes_cluster" "aks" {
  name                = var.clustername
  resource_group_name = var.rg_name
}

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


# 2. Extension AKS (DÉPLACÉ ICI : Unique par cluster)
resource "azurerm_kubernetes_cluster_extension" "backup_extension" {
  name           = "azure-aks-backup"
  cluster_id     = data.azurerm_kubernetes_cluster.aks.id
  extension_type = "microsoft.dataprotection.kubernetes"
  configuration_settings = {
    "configuration.backupStorageLocation.bucket"                = azurerm_storage_container.backup_container.name
    "configuration.backupStorageLocation.config.storageAccount" = azurerm_storage_account.backup_sa.name
    "configuration.backupStorageLocation.config.resourceGroup"  = var.backup_core_rg_name
    "configuration.backupStorageLocation.config.subscriptionId" = data.azurerm_client_config.current.subscription_id
    "credentials.tenantId"                                      = data.azurerm_client_config.current.tenant_id
  }
}

# 3. Trusted Access (DÉPLACÉ ICI : Unique par lien Vault-Cluster)
resource "azurerm_kubernetes_cluster_trusted_access_role_binding" "backup_trusted_access" {
  kubernetes_cluster_id = data.azurerm_kubernetes_cluster.aks.id
  name                  = "backup-trusted-access"
  roles                 = ["Microsoft.DataProtection/backupVaults/backup-operator"]
  source_resource_id    = azurerm_data_protection_backup_vault.cluster_backup_vault.id
}

# 4. TOUS les Role Assignments d'infrastructure (DÉPLACÉS ICI)
# Extension -> Storage
resource "azurerm_role_assignment" "extension_storage_blob" {
  scope                = azurerm_storage_account.backup_sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_kubernetes_cluster_extension.backup_extension.aks_assigned_identity[0].principal_id
}

# Vault -> Cluster & Snapshots
resource "azurerm_role_assignment" "vault_reader_cluster" {
  scope                = data.azurerm_kubernetes_cluster.aks.id
  role_definition_name = "Reader"
  principal_id         = azurerm_data_protection_backup_vault.cluster_backup_vault.identity[0].principal_id
}

# Cluster Identity -> Snapshots RG (Les 3 rôles essentiels)
resource "azurerm_role_assignment" "cluster_snapshot_access" {
  for_each = toset(["Contributor", "Disk Snapshot Contributor", "Data Operator for Managed Disks"])
  scope                = azurerm_resource_group.backup_core_rg.id
  role_definition_name = each.value
  principal_id         = data.azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

# Vault -> Lecture sur le RG de backup (Pour voir les snapshots)
resource "azurerm_role_assignment" "vault_reader_snapshots" {
  scope                = azurerm_resource_group.backup_core_rg.id
  role_definition_name = "Reader"
  principal_id         = azurerm_data_protection_backup_vault.cluster_backup_vault.identity[0].principal_id
}

# Vault -> Contribution sur le RG de backup (Pour gérer les points de restauration)
resource "azurerm_role_assignment" "vault_contributor_snapshots" {
  scope                = azurerm_resource_group.backup_core_rg.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_data_protection_backup_vault.cluster_backup_vault.identity[0].principal_id
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

output "backup_vault_principal_id" {
  value = azurerm_data_protection_backup_vault.cluster_backup_vault.identity[0].principal_id
}

output "backup_container_name" {
  value = azurerm_storage_container.backup_container.name
}
