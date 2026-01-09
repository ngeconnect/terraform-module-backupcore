# --- backupcore / variables.tf ---

variable "clustername" {
  type        = string
  description = "Nom du cluster AKS pour l'extension et le nom du Vault"
}

variable "rg_name" {
  type        = string
  description = "Resource Group où se trouve le cluster AKS (pour le data source)"
}

variable "backup_core_rg_name" {
  type        = string
  description = "Resource Group dédié au Backup (Vault, Storage Account)"
}

variable "db_backup_region" {
  type        = string
  default     = "francecentral"
  description = "Région Azure pour les ressources de backup"
}

variable "environment" {
  type        = string
  description = "Nom de l'environnement (utilisé pour le suffixe du Storage Account)"
}

# Paramètres de la Policy (définis une seule fois ici)
variable "backup_repeating_time_intervals" {
  type        = list(string)
  default     = ["R/2024-01-01T20:00:00+00:00/P1D"]
  description = "Fréquence de backup (ISO 8601)"
}

variable "db_bkp_max_count" {
  type        = number
  default     = 14
  description = "Rétention : nombre de jours de conservation"
}