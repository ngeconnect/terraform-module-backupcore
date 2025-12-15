#===================================================Variables for Backup vault deployments===================================================#
variable "clustername" {
  type        = string
  description = "Clustername"
}


variable "db_bkp_rg" {
  type        = string
  description = "Backup resource group"
}

variable "db_backup_region" {
  type        = map(any)
  default     = { long = "francecentral", short = "frc" }
  description = "Location of the resources this code is going to implement"
}

variable "backup_repeating_time_intervals" {
  type        = list(string)
  default     = ["R/2024-01-01T20:00:00+00:00/P1D"]
  description = "backup interval  schedule, default every 8h "
}

variable "db_bkp_max_count" {
  type        = number
  default     = 14
  description = "Max backup count"
}

